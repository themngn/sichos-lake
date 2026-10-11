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

    Variants {
        model: Quickshell.screens

        PhoneMirrorPanel {}
    }

    Launcher {}
    ClipboardPicker {}
    EmojiPicker {}
    PowerMenu {}
    VolumeOSD {}
    BacklightOSD {}
    KbdBacklightOSD {}
    DisplayModeOSD {}
    MicOSD {}
    Notifications {}
}
