"""Verify the private pinned source locally; report no source contents or paths."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile


COMMIT = "f9632e0ec771668a6f21b37aede01a30110141cb"
ARCHIVE_SHA = "86c8d10d6d6c7644de6011c65f5362baabb5c441539db6fe713d7b45b448e0bf"
LOCK_SHA = "f160ec23242893eae6f65634eb10628b760fe1027ce11d801a253d9d6d1a428a"


def digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest()


try:
    if len(sys.argv) != 3:
        raise ValueError("expected archive and source directory")
    archive_path = Path(sys.argv[1])
    source = Path(sys.argv[2]).resolve(strict=True)
    with archive_path.open("rb") as stream:
        if digest(stream) != ARCHIVE_SHA:
            raise ValueError("archive digest mismatch")
    expected = set()
    with tarfile.open(archive_path) as archive:
        for member in archive:
            components = PurePosixPath(member.name).parts
            if not components or components[0] != "GLEECBTC-kdf-internal-" + COMMIT:
                raise ValueError("unexpected archive root")
            relative = PurePosixPath(*components[1:])
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("invalid archive path")
            target = source.joinpath(*relative.parts)
            if member.isdir():
                if not target.is_dir() or target.is_symlink():
                    raise ValueError("source directory mismatch")
                continue
            expected.add(relative.as_posix())
            if member.issym():
                if not target.is_symlink() or str(target.readlink()) != member.linkname:
                    raise ValueError("source link mismatch")
            elif member.isfile():
                if target.is_symlink() or not target.resolve().is_relative_to(source):
                    raise ValueError("source file escaped root")
                with target.open("rb") as actual, archive.extractfile(member) as original:
                    if digest(actual) != digest(original):
                        raise ValueError("source file mismatch")
            else:
                raise ValueError("unsupported archive entry")
    actual = {
        path.relative_to(source).as_posix()
        for path in source.rglob("*")
        if (path.is_file() or path.is_symlink())
    }
    if actual != expected:
        raise ValueError("unexpected or missing source files")
    with (source / "Cargo.lock").open("rb") as lock:
        if digest(lock) != LOCK_SHA:
            raise ValueError("lockfile digest mismatch")
    result = {"passed": True, "source_commit": COMMIT, "verified_files": len(expected)}
except Exception as error:
    result = {"passed": False, "error_type": type(error).__name__}
print(json.dumps(result, sort_keys=True))
sys.exit(0 if result["passed"] else 1)
