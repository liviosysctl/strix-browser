// A plate that lies over a page: what the browser asks, what it found, what it offers. The
// plates of the shell are smoked glass over a picture the compositor blurs; a page behind one
// may be white, so this one has a ground of its own that nothing shows through.
import QtQuick
import Strix

Surface {
    elevation: "panel"

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.surface
        border.width: Theme.lineHair
        border.color: Theme.border
    }
}
