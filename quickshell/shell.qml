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

    Variants {
        model: Quickshell.screens

        IdleDimOverlay {}
    }

    Launcher {}
    VolumeOSD {}
    BacklightOSD {}
    KbdBacklightOSD {}
    DisplayModeOSD {}
    Notifications {}
}
