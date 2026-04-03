// Copyright (c) 2026 Sebastian Schäfer
// Licensed under MIT License with Commons Clause — see LICENSE for details.
import QtQuick
import QtQuick.Controls
import "."

// Base component for all popup dialogs in picture-show3.
// Provides the standard slide-up-with-bounce enter transition and slide-down
// exit transition, consistent with the panel overlays (ExifPanel, FloatingHud,
// playPausePopup).  Animation parameters come from Theme so there is a single
// source of truth for timing and easing across the whole UI.
//
// Usage: replace  Popup { … }  with  BasePopup { … }
//
// The slide animation works via a _slideOffset property that background and
// contentItem must apply as a Translate transform:
//   transform: Translate { y: root._slideOffset }
// This applies automatically to the default contentItem below.
// Subclasses that define their own background or contentItem must add the
// transform manually.
Popup {
    id: popupBase

    // Vertical slide offset — animated by enter/exit transitions.
    // Background and contentItem overrides must read this via:
    //   transform: Translate { y: root._slideOffset }
    property real _slideOffset: 0

    // Default contentItem — children of the popup land here and slide with
    // the animation.  Subclasses that declare their own contentItem must
    // add `transform: Translate { y: root._slideOffset }` themselves.
    contentItem: Item {
        transform: Translate { y: popupBase._slideOffset }
    }

    // Fade in + nudge up with bounce
    enter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"; from: 0; to: 1
                duration: Theme.animFadeInDuration; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: popupBase; property: "_slideOffset"
                from: Theme.animSlideOffset; to: 0
                duration: Theme.animSlideInDuration
                easing.type: Easing.OutBack; easing.overshoot: Theme.animSlideOvershoot
            }
        }
    }

    // Fade out + nudge down
    exit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"; from: 1; to: 0
                duration: Theme.animFadeOutDuration; easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: popupBase; property: "_slideOffset"; to: Theme.animSlideOffset
                duration: Theme.animFadeOutDuration; easing.type: Easing.InQuad
            }
        }
    }
}
