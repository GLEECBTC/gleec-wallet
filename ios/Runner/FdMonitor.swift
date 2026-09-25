import Foundation
import OSLog

class FdMonitor {


    private var timer: DispatchSourceTimer?
    /// Separate from `timer` because the watermark and the log serve different
    /// purposes: the log is a periodic record a human reads, the watermark is a
    /// peak detector that has to out-sample the thing it measures.
    private var sampleTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.komodo.wallet.fdmonitor", qos: .utility)
    private let logger = Logger(subsystem: "com.komodo.wallet", category: "fd-monitor")
    private var isRunning = false
    private var intervalSeconds: TimeInterval = 60.0
    private var sampleIntervalSeconds: TimeInterval = 0
    private var lastCount: Int = 0
    private let detailThresholdPercent: Double = 0.8

    /// Highest open-FD count seen since `start` or the last `resetPeak`.
    ///
    /// The periodic log cannot answer "did we come close to the limit", because
    /// the events worth catching - a first-time HD activation fanning out across
    /// every chain at once - open and close their sockets well inside one
    /// logging interval. At 60s the log samples roughly 0.4% of a 250ms burst.
    private var peakCount: Int = 0
    private var peakPercentUsed: Double = 0
    private var peakTimestamp: Date?
    /// FD type breakdown for a peak, so a spike says *what* it was made of -
    /// sockets, on the paths that matter here.
    ///
    /// Captured at or shortly before `peakCount`, not necessarily at the exact
    /// sample that set it: a rising burst sets a new peak on nearly every
    /// sample, and the breakdown is too expensive to recompute at that rate.
    /// Read it as the shape of the spike, not as a decomposition of the number.
    private var peakBreakdown: [String: Int] = [:]
    /// Throttles breakdown capture. Counting is a bounded `fcntl` walk; the
    /// breakdown adds an `fstat` and an `F_GETPATH` per descriptor, which is not
    /// something to do at sampling rate.
    private var lastBreakdownCapture: Date?
    private let breakdownMinInterval: TimeInterval = 1.0


    static let shared = FdMonitor()

    private init() {
        NSLog("FDMonitor: Singleton initialized")
    }


    /// - Parameter sampleIntervalSeconds: how often to sample for the peak
    ///   watermark. `0` disables sampling and leaves only the periodic log,
    ///   which is the shipping default - a permanent sub-second timer is a
    ///   power cost a diagnostic should not impose unless it was asked for.
    func start(intervalSeconds: TimeInterval = 60.0, sampleIntervalSeconds: TimeInterval = 0) {
        NSLog("FDMonitor: start() called with interval=%.1f sample=%.3f", intervalSeconds, sampleIntervalSeconds)

        queue.async { [weak self] in
            guard let self = self else { return }

            if self.isRunning {
                NSLog("FDMonitor: Already running, ignoring start request")
                self.logger.info("FD Monitor already running")
                return
            }

            self.intervalSeconds = intervalSeconds
            self.sampleIntervalSeconds = sampleIntervalSeconds
            self.isRunning = true

            NSLog("FDMonitor: Logging initial FD status...")
            self.logFileDescriptorStatus(detailed: false)

            NSLog("FDMonitor: Creating and scheduling timer...")
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
            timer.setEventHandler { [weak self] in
                self?.logFileDescriptorStatus(detailed: false)
            }
            timer.resume()

            self.timer = timer

            if sampleIntervalSeconds > 0 {
                let sampleTimer = DispatchSource.makeTimerSource(queue: self.queue)
                sampleTimer.schedule(deadline: .now() + sampleIntervalSeconds, repeating: sampleIntervalSeconds)
                sampleTimer.setEventHandler { [weak self] in
                    self?.sampleForPeak()
                }
                sampleTimer.resume()

                self.sampleTimer = sampleTimer
                NSLog("FDMonitor: Peak sampling enabled at %.3fs", sampleIntervalSeconds)
                self.logger.notice("FD peak sampling enabled at \(sampleIntervalSeconds, privacy: .public)s")
            }

            NSLog("FDMonitor: Started successfully with interval=%.1f seconds", intervalSeconds)
            self.logger.notice("FD Monitor started with interval: \(intervalSeconds, privacy: .public) seconds")

            NSLog("FDMonitor: Logging detailed status for immediate verification...")
            self.logFileDescriptorStatus(detailed: true)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }

            if !self.isRunning {
                self.logger.info("FD Monitor not running")
                return
            }

            self.timer?.cancel()
            self.timer = nil
            self.sampleTimer?.cancel()
            self.sampleTimer = nil
            self.isRunning = false

            self.logger.info("FD Monitor stopped")
        }
    }

    func getCurrentCount() -> [String: Any] {
        var result: [String: Any] = [:]

        queue.sync {
            let fdInfo = self.getFileDescriptorInfo()
            // Fold the live reading into the watermark so a caller polling this
            // does not read a peak that its own sample has already beaten.
            self.recordPeak(fdInfo)

            result = [
                "openCount": fdInfo.openCount,
                "tableSize": fdInfo.tableSize,
                "softLimit": fdInfo.softLimit,
                "hardLimit": fdInfo.hardLimit,
                "percentUsed": fdInfo.percentUsed,
                "peakCount": self.peakCount,
                "peakPercentUsed": self.peakPercentUsed,
                "peakTimestamp": self.peakTimestamp.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "peakBreakdown": self.peakBreakdown,
                "sampleIntervalSeconds": self.sampleIntervalSeconds,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        }

        return result
    }

    /// Clears the watermark so the next reading measures one named phase.
    ///
    /// Without this a peak set during startup masks everything that follows,
    /// and the interesting phase - login, activation - is exactly the one that
    /// comes after startup.
    func resetPeak() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let previous = self.peakCount
            self.peakCount = 0
            self.peakPercentUsed = 0
            self.peakTimestamp = nil
            self.peakBreakdown = [:]
            self.lastBreakdownCapture = nil
            self.logger.notice("FD peak reset (was \(previous, privacy: .public))")
            NSLog("FDMonitor: Peak reset (was %d)", previous)
        }
    }


    private struct FdInfo {
        let openCount: Int
        let tableSize: Int
        let softLimit: Int
        let hardLimit: Int
        let percentUsed: Double
    }

    private func getFileDescriptorInfo() -> FdInfo {
        let tableSize = Int(getdtablesize())

        var rlimit = rlimit()
        getrlimit(RLIMIT_NOFILE, &rlimit)
        let softLimit = Int(rlimit.rlim_cur)
        let hardLimit = Int(rlimit.rlim_max)

        var openCount = 0
        for fd in 0..<tableSize {
            let fd32 = Int32(fd)
            errno = 0
            let flags = fcntl(fd32, F_GETFD, 0)
            if flags != -1 || errno != EBADF {
                openCount += 1
            }
        }

        let percentUsed = softLimit > 0 ? (Double(openCount) / Double(softLimit)) * 100.0 : 0.0

        return FdInfo(
            openCount: openCount,
            tableSize: tableSize,
            softLimit: softLimit,
            hardLimit: hardLimit,
            percentUsed: percentUsed
        )
    }

    /// The sampling-rate path: count, and record if it is a new high.
    private func sampleForPeak() {
        recordPeak(getFileDescriptorInfo())
    }

    private func recordPeak(_ fdInfo: FdInfo) {
        guard fdInfo.openCount > peakCount else { return }

        peakCount = fdInfo.openCount
        peakPercentUsed = fdInfo.percentUsed
        peakTimestamp = Date()

        // A rising burst sets a new peak on almost every sample. Capture the
        // breakdown for the first one and then at most once a second, which
        // keeps the expensive walk off the hot path while still attributing the
        // spike.
        let now = Date()
        if let last = lastBreakdownCapture, now.timeIntervalSince(last) < breakdownMinInterval {
            return
        }
        lastBreakdownCapture = now
        peakBreakdown = collectFdBreakdown()
    }

    private func logFileDescriptorStatus(detailed: Bool) {
        let fdInfo = getFileDescriptorInfo()
        recordPeak(fdInfo)

        let statusMsg = String(format: "FD Status: open=%d/%d (%.1f%%), peak=%d (%.1f%%), table_size=%d, soft_limit=%d, hard_limit=%d",
                              fdInfo.openCount, fdInfo.softLimit, fdInfo.percentUsed,
                              peakCount, peakPercentUsed,
                              fdInfo.tableSize, fdInfo.softLimit, fdInfo.hardLimit)

        NSLog("FDMonitor: %@", statusMsg)
        logger.info("\(statusMsg, privacy: .public)")

        if !peakBreakdown.isEmpty {
            let peakSummary = peakBreakdown.sorted { $0.value > $1.value }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            NSLog("FDMonitor: Peak breakdown: %@", peakSummary)
            logger.info("Peak breakdown: \(peakSummary, privacy: .public)")
        }

        let shouldLogDetails = detailed ||
                               fdInfo.percentUsed > (detailThresholdPercent * 100.0) ||
                               (fdInfo.openCount - lastCount) > 50

        if shouldLogDetails {
            NSLog("FDMonitor: FD count approaching limit or significant increase detected, logging details...")
            logger.info("FD count approaching limit or significant increase detected, logging details...")
            logDetailedFileDescriptors(maxSamples: 50)
        }

        lastCount = fdInfo.openCount
    }

    /// Counts open descriptors by type across the whole table.
    ///
    /// Unlike [`logDetailedFileDescriptors`] this is not sampled - a socket
    /// count that stops at 50 cannot be compared against a limit of 256.
    private func collectFdBreakdown() -> [String: Int] {
        let tableSize = Int(getdtablesize())
        var fdsByType: [String: Int] = [:]

        for fd in 0..<tableSize {
            let fd32 = Int32(fd)
            errno = 0
            let flags = fcntl(fd32, F_GETFD, 0)

            if flags == -1 && errno == EBADF {
                continue // Not open
            }

            var st = stat()
            let typeStr = fstat(fd32, &st) == 0 ? Self.describe(mode: st.st_mode) : "unknown"
            fdsByType[typeStr, default: 0] += 1
        }

        return fdsByType
    }

    private static func describe(mode: mode_t) -> String {
        switch mode & S_IFMT {
        case S_IFREG: return "file"
        case S_IFDIR: return "dir"
        case S_IFSOCK: return "socket"
        case S_IFIFO: return "pipe"
        case S_IFCHR: return "char_dev"
        case S_IFBLK: return "block_dev"
        default: return "unknown"
        }
    }

    func logDetailedStatus() {
        queue.async { [weak self] in
            self?.logFileDescriptorStatus(detailed: true)
        }
    }

    private func logDetailedFileDescriptors(maxSamples: Int) {
        let tableSize = Int(getdtablesize())
        var logged = 0
        var fdsByType: [String: Int] = [:]

        for fd in 0..<tableSize where logged < maxSamples {
            let fd32 = Int32(fd)
            errno = 0
            let flags = fcntl(fd32, F_GETFD, 0)

            if flags == -1 && errno == EBADF {
                continue // Not open
            }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathResult = fcntl(fd32, F_GETPATH, &pathBuffer)
            let path = pathResult != -1 ? String(cString: pathBuffer) : "<unknown>"

            var st = stat()
            let typeStr = fstat(fd32, &st) == 0 ? Self.describe(mode: st.st_mode) : "unknown"

            fdsByType[typeStr, default: 0] += 1

            if logged < 20 { // Only log first 20 individual FDs to avoid spam
                logger.debug("  FD \(fd): type=\(typeStr) path=\(path)")
            }

            logged += 1
        }

        logger.info("FD breakdown by type:")
        for (type, count) in fdsByType.sorted(by: { $0.value > $1.value }) {
            logger.info("  \(type): \(count)")
        }
    }
}
