//@ pragma UseQApplication
import Quickshell
import "./modules"

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Variants {
        model: Quickshell.screens

        NowPlaying {}
    }

    Launcher {}
    VolumeOSD {}
    Notifications {}
}
