def can_build(env, platform):
    # The module is an editor/IDE backend. It has no platform-specific
    # dependencies beyond the OS process and image APIs already in core.
    return platform in ("linuxbsd", "windows", "macos", "x11", "osx")


def configure(env):
    pass
