/*
 * The popup. A colour band greets you by name and changes with the time of
 * day; favorites are a grid of colour tiles, all apps are grouped under
 * coloured letter badges.
 *
 * Still flatkit underneath: Inter, flat fills, 1px borders that become a 2px
 * accent ring on focus, a solid accent selection, and no animation, so the
 * keyboard never waits on anything.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.plasma5support as P5Support

Item {
    id: root

    required property var menuItem
    required property var rootModel
    required property var recentModel
    required property var runnerModel
    required property var systemModel

    readonly property real px: Kirigami.Units.gridUnit / 18

    Layout.minimumWidth: Math.round(460 * px)
    Layout.minimumHeight: Math.round(600 * px)
    Layout.preferredWidth: Math.round(500 * px)
    Layout.preferredHeight: Math.round(640 * px)

    // flatkit's KitColors, derived from the Plasma colour scheme the same
    // way flatkit's KdeColors does.
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    readonly property color cBackground: Kirigami.Theme.backgroundColor
    readonly property color cText: Kirigami.Theme.textColor
    readonly property color cSurface: buttonTheme.Kirigami.Theme.backgroundColor
    readonly property color cHover: mix(cSurface, cText, 0.07)
    readonly property color cPressed: mix(cSurface, cText, 0.14)
    readonly property color cBorder: mix(cBackground, cText, 0.18)
    readonly property color cBorderStrong: mix(cBackground, cText, 0.35)
    readonly property color cTextDim: mix(cBackground, cText, 0.6)
    // The accent comes straight from kdeglobals, as flatkit's KdeColors
    // reads it: a Plasma style can carry its own highlight colour, which is
    // what Kirigami.Theme reports inside a widget, and that need not be the
    // accent picked in System Settings.
    property color systemAccent: "transparent"
    readonly property color cAccent: systemAccent.a > 0 ? systemAccent : Kirigami.Theme.highlightColor
    readonly property color cOnAccent: systemAccent.a > 0
        ? (luminance(systemAccent) > 0.45 ? "black" : "white")
        : Kirigami.Theme.highlightedTextColor
    readonly property color cFocus: cAccent

    function luminance(c) {
        const ch = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    // KConfig colours are "r,g,b", "r,g,b,a" or "#rrggbb".
    function parseKColor(v) {
        v = String(v ?? "").trim();
        if (v.startsWith("#") && (v.length === 7 || v.length === 9)) {
            return Qt.color(v);
        }
        const parts = v.split(",").map(n => parseInt(n, 10));
        if (parts.length < 3 || parts.some(n => isNaN(n))) {
            return null;
        }
        return Qt.rgba(parts[0] / 255, parts[1] / 255, parts[2] / 255, 1);
    }

    P5Support.DataSource {
        id: accentReader
        engine: "executable"
        readonly property string command: "kreadconfig6 --group General --key AccentColor; echo '|'; "
            + "kreadconfig6 --group Colors:Selection --key BackgroundNormal"
        onNewData: (source, data) => {
            disconnectSource(source);
            const [accent, selection] = String(data.stdout ?? "").split("|");
            const c = root.parseKColor(accent) ?? root.parseKColor(selection);
            if (c) {
                root.systemAccent = c;
            }
        }
        function refresh() {
            disconnectSource(command);
            connectSource(command);
        }
    }
    readonly property bool dark: cBackground.hslLightness < 0.5

    // Flat, saturated colours for tiles and badges. Each app always gets the
    // same one, picked from its name.
    readonly property var hues: ["#ff6b6b", "#ff922b", "#fcc419", "#20c997",
        "#22b8cf", "#4c6ef5", "#845ef7", "#cc5de8", "#f06595"]
    function colorFor(name) {
        const s = String(name ?? "");
        let h = 0;
        for (let i = 0; i < s.length; i++) {
            h = (h * 31 + s.charCodeAt(i)) >>> 0;
        }
        return hues[h % hues.length];
    }
    function tint(c, amount) {
        return mix(cSurface, Qt.color(c), amount);
    }

    readonly property real radius: 6 * px
    readonly property real rowHeight: Math.round(44 * px)

    Item {
        id: buttonTheme
        Kirigami.Theme.colorSet: Kirigami.Theme.Button
        Kirigami.Theme.inherit: false
    }

    // Inter ships with the widget, as it does with flatkit.
    FontLoader { id: interRegular; source: "../fonts/Inter-Regular.ttf" }
    FontLoader { source: "../fonts/Inter-Medium.ttf" }
    FontLoader { source: "../fonts/Inter-SemiBold.ttf" }
    readonly property string fontFamily: interRegular.status === FontLoader.Ready ? interRegular.name : Kirigami.Theme.defaultFont.family
    readonly property real fontSize: 14 * px
    readonly property real smallSize: 12 * px

    KCoreAddons.KUser { id: kuser }
    readonly property string firstName: {
        const full = (kuser.fullName || "").trim();
        return full.length > 0 ? full.split(" ")[0] : kuser.loginName;
    }

    // The time of day sets the greeting and the band's colour.
    property date now: new Date()
    Timer {
        interval: 30000
        repeat: true
        running: root.menuItem.expanded
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
    readonly property int hour: now.getHours()
    readonly property var mood: hour < 5 ? { greet: i18n("Up late"), color: "#3b3f8f" }
        : hour < 12 ? { greet: i18n("Good morning"), color: "#f08c00" }
        : hour < 17 ? { greet: i18n("Good afternoon"), color: "#1c7ed6" }
        : hour < 21 ? { greet: i18n("Good evening"), color: "#7048e8" }
        : { greet: i18n("Good night"), color: "#3b3f8f" }

    // 0 favorites, 1 recent, 2 all applications.
    property int tab: Plasmoid.configuration.startTab
    readonly property bool searching: search.text.length > 0
    readonly property bool gridMode: !searching && tab === 0
    readonly property Item view: gridMode ? grid : list
    readonly property int columns: 4

    readonly property var allAppsModel: rootModel.count > 0 ? rootModel.modelForRow(0) : null
    readonly property var currentModel: {
        if (searching) {
            return runnerModel.count > 0 ? runnerModel.modelForRow(0) : null;
        }
        switch (tab) {
        case 0: return rootModel.favoritesModel;
        case 1: return recentModel;
        default: return allAppsModel;
        }
    }

    function reset() {
        accentReader.refresh();
        actions.close();
        search.text = "";
        tab = Plasmoid.configuration.startTab;
        list.currentIndex = 0;
        grid.currentIndex = 0;
        list.positionViewAtBeginning();
        grid.positionViewAtBeginning();
        search.forceActiveFocus();
    }

    function move(delta) {
        if (view.count === 0) {
            return;
        }
        view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + delta));
    }

    function activate(index) {
        if (!currentModel || index < 0 || index >= view.count) {
            return;
        }
        currentModel.trigger(index, "", null);
        menuItem.expanded = false;
    }

    function openActions(index) {
        const row = view.itemAtIndex(index);
        if (!row || !row.actionList || row.actionList.length === 0) {
            return;
        }
        actions.rowIndex = index;
        actions.entries = row.actionList.filter(a => a.type !== "title");
        const p = row.mapToItem(root, 0, row.height);
        actions.x = Math.max(12 * px, Math.min(root.width - actions.width - 12 * px, p.x + row.width / 3));
        actions.y = p.y;
        if (actions.y + actions.implicitHeight > root.height) {
            actions.y = Math.max(0, p.y - row.height - actions.implicitHeight);
        }
        actions.open();
    }

    Connections {
        target: root.menuItem
        function onExpandedChanged() {
            if (root.menuItem.expanded) {
                root.reset();
            }
        }
    }

    onSearchingChanged: {
        view.currentIndex = 0;
    }
    onTabChanged: {
        list.currentIndex = 0;
        grid.currentIndex = 0;
    }

    Rectangle {
        anchors.fill: parent
        color: root.cBackground
        radius: root.radius
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The band: greeting, date, and the search field sitting on it.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: bandColumn.implicitHeight + 28 * root.px
            color: root.mood.color
            topLeftRadius: root.radius
            topRightRadius: root.radius
            clip: true

            // A few flat circles for some shape, in the band's own colour.
            Rectangle {
                width: 150 * root.px; height: width; radius: width / 2
                x: parent.width - width * 0.55; y: -width * 0.45
                color: Qt.lighter(root.mood.color, 1.18)
            }
            Rectangle {
                width: 70 * root.px; height: width; radius: width / 2
                x: parent.width - 175 * root.px; y: 34 * root.px
                color: Qt.lighter(root.mood.color, 1.1)
            }

            ColumnLayout {
                id: bandColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14 * root.px
                spacing: 2 * root.px

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * root.px

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: root.firstName.length > 0 ? root.mood.greet + ", " + root.firstName
                                : root.mood.greet
                            color: "white"
                            font.family: root.fontFamily
                            font.pixelSize: 22 * root.px
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            text: Qt.formatDateTime(root.now, "dddd, d MMMM · ") + Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat))
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.family: root.fontFamily
                            font.pixelSize: 13 * root.px
                        }
                    }

                }

                // Search field: KitTextField, a size up.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 10 * root.px
                    implicitHeight: Math.round(40 * root.px)
                    radius: root.radius
                    color: root.cSurface
                    border.width: search.activeFocus ? 2 : 0
                    border.color: root.cFocus

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12 * root.px
                        anchors.rightMargin: 12 * root.px
                        spacing: 8 * root.px

                        Kirigami.Icon {
                            source: "search"
                            color: root.cTextDim
                            isMask: true
                            implicitWidth: 16 * root.px
                            implicitHeight: 16 * root.px
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            focus: true
                            clip: true
                            color: root.cText
                            selectionColor: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.3)
                            selectedTextColor: root.cText
                            font.family: root.fontFamily
                            font.pixelSize: 15 * root.px
                            cursorDelegate: Rectangle {
                                width: 1.5
                                color: root.cAccent
                                visible: search.cursorVisible
                            }

                            onTextChanged: root.runnerModel.query = text

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: search.text.length === 0
                                text: i18n("Type to search apps, settings, files, sums…")
                                color: root.cTextDim
                                font: search.font
                                elide: Text.ElideRight
                            }

                            Keys.onPressed: event => {
                                const ctrl = event.modifiers & Qt.ControlModifier;
                                const step = root.gridMode ? root.columns : 1;
                                if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                                    root.move(step);
                                } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                                    root.move(-step);
                                } else if (root.gridMode && event.key === Qt.Key_Right) {
                                    root.move(1);
                                } else if (root.gridMode && event.key === Qt.Key_Left) {
                                    root.move(-1);
                                } else if (event.key === Qt.Key_PageDown) {
                                    root.move(8 * step);
                                } else if (event.key === Qt.Key_PageUp) {
                                    root.move(-8 * step);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.activate(root.view.currentIndex);
                                } else if (event.key === Qt.Key_Escape) {
                                    if (search.text.length > 0) {
                                        search.text = "";
                                    } else {
                                        root.menuItem.expanded = false;
                                    }
                                } else if (event.key === Qt.Key_Tab && !root.searching) {
                                    root.tab = (root.tab + 1) % 3;
                                } else if (event.key === Qt.Key_Backtab && !root.searching) {
                                    root.tab = (root.tab + 2) % 3;
                                } else if (event.key === Qt.Key_Menu
                                           || (event.key === Qt.Key_Right && search.cursorPosition === search.text.length)) {
                                    root.openActions(root.view.currentIndex);
                                } else if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                                    root.activate(event.key - Qt.Key_1);
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }

        // KitSegmented: favorites, recent, all.
        Rectangle {
            visible: !root.searching
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12 * root.px
            Layout.bottomMargin: 8 * root.px
            implicitWidth: segments.implicitWidth + 4
            implicitHeight: Math.round(32 * root.px)
            radius: root.radius
            color: root.cSurface
            border.width: 1
            border.color: root.cBorder

            Row {
                id: segments
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: [
                        { label: i18n("Favorites"), icon: "favorite" },
                        { label: i18n("Recent"), icon: "chronometer" },
                        { label: i18n("All apps"), icon: "view-list-icons" },
                    ]

                    delegate: Rectangle {
                        id: segment
                        required property int index
                        required property var modelData
                        readonly property bool on: root.tab === index
                        width: Math.max(104 * root.px, segmentRow.implicitWidth + 24 * root.px)
                        height: Math.round(28 * root.px)
                        radius: root.radius - 2
                        color: on ? root.cAccent : (segmentMouse.pressed ? root.cPressed : (segmentMouse.containsMouse ? root.cHover : "transparent"))

                        Row {
                            id: segmentRow
                            anchors.centerIn: parent
                            spacing: 6 * root.px

                            Kirigami.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: segment.modelData.icon
                                implicitWidth: 14 * root.px
                                implicitHeight: 14 * root.px
                                isMask: true
                                color: segment.on ? root.cOnAccent : root.cText
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: segment.modelData.label
                                color: segment.on ? root.cOnAccent : root.cText
                                font.family: root.fontFamily
                                font.pixelSize: 13 * root.px
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: segmentMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.tab = segment.index;
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: root.cBorder
            visible: root.searching
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Favorites: colour tiles.
            GridView {
                id: grid
                anchors.fill: parent
                anchors.leftMargin: 10 * root.px
                anchors.rightMargin: 10 * root.px
                visible: root.gridMode
                clip: true
                model: root.gridMode ? root.currentModel : null
                cellWidth: Math.floor(width / root.columns)
                cellHeight: Math.round(104 * root.px)
                currentIndex: 0
                topMargin: 4 * root.px
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                highlightFollowsCurrentItem: false
                keyNavigationEnabled: false
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                onCountChanged: if (currentIndex < 0 || currentIndex >= count) currentIndex = 0

                delegate: MouseArea {
                    id: tile

                    required property int index
                    required property var model
                    readonly property var actionList: model.hasActionList ? model.actionList : []
                    readonly property bool selected: GridView.isCurrentItem
                    readonly property color hue: root.colorFor(model.display)

                    width: grid.cellWidth
                    height: grid.cellHeight
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: mouse => {
                        grid.currentIndex = index;
                        if (mouse.button === Qt.RightButton) {
                            root.openActions(index);
                        } else {
                            root.activate(index);
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4 * root.px
                        radius: root.radius * 1.5
                        color: tile.selected ? tile.hue : root.tint(tile.hue, tile.containsMouse ? (root.dark ? 0.35 : 0.28) : (root.dark ? 0.22 : 0.16))
                        border.width: tile.selected ? 2 : 0
                        border.color: root.cFocus

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 12 * root.px
                            spacing: 8 * root.px

                            // The icon sits on a white disc so it reads on any tile.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.round(48 * root.px)
                                height: width
                                radius: width / 2
                                color: tile.selected ? "white" : Qt.rgba(1, 1, 1, root.dark ? 0.12 : 0.7)

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: tile.model.decoration
                                    implicitWidth: 32 * root.px
                                    implicitHeight: 32 * root.px
                                    animated: false
                                }
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.model.display ?? ""
                                color: tile.selected ? "white" : root.cText
                                font.family: root.fontFamily
                                font.pixelSize: root.smallSize
                                font.weight: tile.selected ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    spacing: 10 * root.px

                    Kirigami.Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: "favorite"
                        implicitWidth: 48 * root.px
                        implicitHeight: 48 * root.px
                        color: root.colorFor("favorites")
                        isMask: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: i18n("Pin your go-to apps here")
                        color: root.cText
                        font.family: root.fontFamily
                        font.pixelSize: 15 * root.px
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: i18n("Right-click any app and choose Add to Favorites")
                        color: root.cTextDim
                        font.family: root.fontFamily
                        font.pixelSize: root.smallSize
                    }
                }
            }

            // Recent, all apps and search results: one list.
            ListView {
                id: list
                anchors.fill: parent
                visible: !root.gridMode
                clip: true
                model: root.gridMode ? null : root.currentModel
                currentIndex: 0
                topMargin: 2 * root.px
                bottomMargin: 4 * root.px
                boundsBehavior: Flickable.StopAtBounds
                // Selection jumps into view; it never scrolls smoothly.
                highlightMoveDuration: 0
                highlightResizeDuration: 0
                highlightFollowsCurrentItem: false
                keyNavigationEnabled: false
                reuseItems: true

                // All apps are grouped under a coloured badge per letter.
                section.property: !root.searching && root.tab === 2 ? "display" : ""
                section.criteria: ViewSection.FirstCharacter
                section.delegate: Item {
                    id: header
                    required property string section
                    width: ListView.view.width
                    height: Math.round(32 * root.px)

                    Rectangle {
                        id: badge
                        x: 12 * root.px
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(22 * root.px)
                        height: width
                        radius: root.radius
                        color: root.colorFor(header.section.toUpperCase() + "badge")

                        Text {
                            anchors.centerIn: parent
                            text: header.section.toUpperCase()
                            color: "white"
                            font.family: root.fontFamily
                            font.pixelSize: 12 * root.px
                            font.weight: Font.Bold
                        }
                    }
                    Rectangle {
                        anchors.left: badge.right
                        anchors.leftMargin: 8 * root.px
                        anchors.right: parent.right
                        anchors.rightMargin: 12 * root.px
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: root.cBorder
                    }
                }

                QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                    id: scrollBar
                    policy: list.contentHeight > list.height ? QQC2.ScrollBar.AlwaysOn : QQC2.ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: root.cBorderStrong
                    }
                    background: null
                }

                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                onCountChanged: if (currentIndex < 0 || currentIndex >= count) currentIndex = 0
                onModelChanged: currentIndex = 0

                delegate: MouseArea {
                    id: row

                    required property int index
                    required property var model
                    readonly property var actionList: model.hasActionList ? model.actionList : []
                    readonly property bool selected: ListView.isCurrentItem

                    width: ListView.view.width - (scrollBar.visible ? 8 : 0)
                    height: root.rowHeight
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: mouse => {
                        list.currentIndex = index;
                        if (mouse.button === Qt.RightButton) {
                            root.openActions(index);
                        } else {
                            root.activate(index);
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 6 * root.px
                        anchors.rightMargin: 6 * root.px
                        radius: root.radius
                        color: row.selected ? root.cAccent : (row.containsMouse ? root.cHover : "transparent")
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14 * root.px
                        anchors.rightMargin: 16 * root.px
                        spacing: 12 * root.px

                        Kirigami.Icon {
                            source: row.model.decoration
                            implicitWidth: 28 * root.px
                            implicitHeight: 28 * root.px
                            animated: false
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: row.model.display ?? ""
                                color: row.selected ? root.cOnAccent : root.cText
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize
                                font.weight: row.selected ? Font.Medium : Font.Normal
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: (row.model.description ?? "") !== row.model.display ? (row.model.description ?? "") : ""
                                color: row.selected ? Qt.rgba(root.cOnAccent.r, root.cOnAccent.g, root.cOnAccent.b, 0.8) : root.cTextDim
                                font.family: root.fontFamily
                                font.pixelSize: root.smallSize
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                            }
                        }

                        // A keycap for the first nine rows.
                        Rectangle {
                            visible: row.index < 9
                            implicitWidth: keycap.implicitWidth + 10 * root.px
                            implicitHeight: Math.round(20 * root.px)
                            radius: 4 * root.px
                            color: row.selected ? Qt.rgba(1, 1, 1, 0.2) : root.cSurface
                            border.width: row.selected ? 0 : 1
                            border.color: root.cBorder

                            Text {
                                id: keycap
                                anchors.centerIn: parent
                                text: "Alt " + (row.index + 1)
                                color: row.selected ? root.cOnAccent : root.cTextDim
                                font.family: root.fontFamily
                                font.pixelSize: 11 * root.px
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48 * root.px
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: list.count === 0
                    text: root.searching ? (root.runnerModel.querying ? "" : i18n("Nothing here. Try fewer letters?"))
                        : root.tab === 1 ? i18n("Open a few apps and they'll show up here.")
                        : ""
                    color: root.cTextDim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.cBorder }

        // Footer: session buttons from Plasma's system model.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12 * root.px
            Layout.rightMargin: 6 * root.px
            implicitHeight: Math.round(40 * root.px)
            spacing: 2

            Item { Layout.fillWidth: true }

            Repeater {
                model: root.systemModel

                delegate: Rectangle {
                    id: sysButton
                    required property int index
                    required property var model
                    readonly property var shown: ["lock-screen", "logout", "reboot", "shutdown"]
                    readonly property bool danger: model.favoriteId === "shutdown"
                    visible: shown.indexOf(model.favoriteId) >= 0
                    implicitWidth: Math.round(30 * root.px)
                    implicitHeight: Math.round(30 * root.px)
                    radius: root.radius
                    color: sysMouse.containsMouse ? (danger ? Kirigami.Theme.negativeTextColor : root.cHover) : "transparent"

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: sysButton.model.decoration
                        implicitWidth: 16 * root.px
                        implicitHeight: 16 * root.px
                        color: sysButton.danger && sysMouse.containsMouse ? "white" : root.cText
                        isMask: true
                    }

                    MouseArea {
                        id: sysMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.systemModel.trigger(sysButton.index, "", null);
                            root.menuItem.expanded = false;
                        }
                    }

                    QQC2.ToolTip.visible: sysMouse.containsMouse
                    QQC2.ToolTip.text: sysButton.model.display
                    QQC2.ToolTip.delay: 0
                }
            }
        }
    }

    // KitMenu: an item's actions (favorites, jump-list entries such as
    // "New Private Window", edit, uninstall), shown in one frame and driven
    // by the arrow keys.
    QQC2.Popup {
        id: actions

        property int rowIndex: -1
        property var entries: []

        width: Math.round(260 * root.px)
        padding: 4 * root.px
        modal: false
        focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        enter: null
        exit: null

        onOpened: {
            actionList.currentIndex = actionList.firstEnabled(0, 1);
            actionList.forceActiveFocus();
        }
        onClosed: search.forceActiveFocus()

        function run(i) {
            const a = entries[i];
            if (!a || a.type === "separator" || !root.currentModel) {
                return;
            }
            close();
            root.currentModel.trigger(rowIndex, a.actionId, a.actionArgument);
            // Favorites changes keep the menu open; anything that starts
            // something closes it.
            if (!String(a.actionId).toLowerCase().includes("favorite")) {
                root.menuItem.expanded = false;
            }
        }

        background: Rectangle {
            color: root.cSurface
            radius: root.radius
            border.width: 1
            border.color: root.cBorderStrong
        }

        contentItem: ListView {
            id: actionList
            implicitHeight: contentHeight
            model: actions.entries
            interactive: false
            keyNavigationEnabled: false

            function firstEnabled(from, step) {
                for (let i = from; i >= 0 && i < actions.entries.length; i += step) {
                    if (actions.entries[i].type !== "separator") {
                        return i;
                    }
                }
                return currentIndex;
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    currentIndex = firstEnabled(currentIndex + 1, 1);
                } else if (event.key === Qt.Key_Up) {
                    currentIndex = firstEnabled(currentIndex - 1, -1);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    actions.run(currentIndex);
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) {
                    actions.close();
                } else {
                    return;
                }
                event.accepted = true;
            }

            delegate: Item {
                id: entry
                required property int index
                required property var modelData
                readonly property bool separator: modelData.type === "separator"
                width: ListView.view.width
                height: separator ? 9 : Math.round(28 * root.px)

                Rectangle {
                    visible: entry.separator
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: root.cBorder
                }

                Rectangle {
                    visible: !entry.separator
                    anchors.fill: parent
                    radius: root.radius - 2
                    color: actionList.currentIndex === entry.index ? root.cAccent
                        : (entryMouse.containsMouse ? root.cHover : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8 * root.px
                        anchors.rightMargin: 8 * root.px
                        spacing: 8 * root.px

                        Kirigami.Icon {
                            source: entry.modelData.icon ?? ""
                            implicitWidth: 16 * root.px
                            implicitHeight: 16 * root.px
                            visible: (entry.modelData.icon ?? "") !== ""
                        }

                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.text ?? ""
                            color: actionList.currentIndex === entry.index ? root.cOnAccent : root.cText
                            font.family: root.fontFamily
                            font.pixelSize: 13 * root.px
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: actionList.currentIndex = entry.index
                        onClicked: actions.run(entry.index)
                    }
                }
            }
        }
    }

    Component.onCompleted: reset()
}
