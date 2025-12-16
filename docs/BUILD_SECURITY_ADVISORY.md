# Build Security Advisory for Gleec Wallet

## Critical Flags for Production Builds

When building the Gleec Wallet for production, **always** use the following flags:

```bash
--enforce-lockfile  # When running 'flutter pub get'
--no-pub            # When running 'flutter build'
--no-web-resources-cdn  # When building for web
```

## Security Justification

### `--enforce-lockfile`

This flag ensures that dependencies are installed **exactly** as specified in the `pubspec.lock` file with no automatic updates.

**Why this matters:**

- **Prevents supply chain attacks**: Without this flag, the build process might automatically update dependencies, potentially introducing malicious code.
- **Ensures reproducible builds**: Every build uses identical dependencies, allowing verification that binaries match source code.
- **Maintains audit trail**: Security teams can review and approve specific dependency versions before they reach production.
- **Enforces cryptographic hash verification**: The `pubspec.lock` file contains cryptographic hashes of each package that are verified during installation, ensuring the exact reviewed code is used.
- **Prevents version tag ambiguity**: Even with identical version tags (e.g., v1.2.3), package repositories may serve different code at different times. The lockfile's hash verification prevents this security risk.

### `--no-pub`

This flag prevents the Flutter tool from automatically running `pub get` during the build process.

**Why this matters:**

- **Prevents unexpected dependency changes**: No new packages will be downloaded during the build process.
- **Isolates build environments**: Ensures builds don't depend on external package repositories being available.
- **Reduces attack surface**: Eliminates an entire class of potential build-time vulnerabilities by preventing network access to package repositories.

### `--no-web-resources-cdn`

This flag prevents Flutter from using Google-hosted CDNs for engine resources when building for web.

**Why this matters:**

- **Eliminates third-party hosting dependencies**: All resources are bundled locally, removing the security risk of CDN compromise.
- **Ensures regulatory compliance**: Many financial applications operate under regulations restricting external resource loading.
- **Improves privacy**: Prevents user browsers from making connections to third-party servers when using the application.
- **Guarantees availability**: Application will function even if external CDNs become unavailable or are blocked in certain regions.
- **Simplifies security audits**: All resources are contained within your deployment, making the security perimeter clearer.

## Implementation Recommendations

1. **CI/CD Pipeline Integration**: Configure your CI/CD pipelines to always include these flags.
2. **Build Script Enforcement**: Update all build scripts to include these flags by default.
3. **Dependency Updates Process**: Establish a controlled process for updating dependencies that includes:
   - Security review of proposed updates
   - Testing in isolation
   - Formal approval before publishing new lock files
4. **Lockfile Verification**: Implement a verification step that compares the hash of the lockfile used for building against a known-good reference hash.

## Example Build Commands

For local development:

```bash
flutter pub get --enforce-lockfile
flutter build apk --no-pub
```

For web builds:

```bash
flutter pub get --enforce-lockfile
flutter build web --csp --no-web-resources-cdn --no-pub
```

For Docker builds:

```bash
docker run --rm -v ./build:/app/build gleec/gleec-wallet:latest bash -c "flutter pub get --enforce-lockfile && flutter build apk --no-pub --release"
```

## Compliance and Audit

Document all production builds with:

- Hash of pubspec.lock file used
- Build environment details
- Output binary hashes

This documentation facilitates security audits and helps maintain the chain of custody for all production artifacts.

## Technical Details: Package Resolution Risks

Without `--enforce-lockfile`, the following risks may occur even when package versions appear consistent:

1. **Floating references**: Dependencies of your dependencies might not be locked, causing different code to be resolved at build time.
2. **Repository substitution**: A compromised package repository could serve malicious code with the same version number.
3. **Git dependencies**: For packages hosted on Git, the same tag could be moved to point to different commits.
4. **Yanked versions**: A previously reviewed version might be yanked and replaced with a new one having the same version identifier.

The cryptographic hashes in the lockfile protect against all these scenarios by verifying the actual content rather than just the version identifier.
