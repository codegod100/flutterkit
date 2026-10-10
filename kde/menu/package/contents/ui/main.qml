/*
 * Flatkit Menu: a Plasma application launcher in the flatkit style. Flat
 * surfaces, a single accent, nothing that fades or slides, and everything
 * reachable from the keyboard.
 *
 * Data comes from Plasma's own menu models (the ones Kickoff uses), so apps,
 * favorites, recent use and search results match the rest of the desktop.
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: menu

    Plasmoid.icon: Plasmoid.configuration.icon
    // Pressing Meta on its own (or the widget's shortcut) toggles the popup;
    // X-Plasma-Provides org.kde.plasma.launchermenu in metadata.json is what
    // routes Meta here.
    activationTogglesExpanded: true
    preferredRepresentation: compactRepresentation
    hideOnWindowDeactivate: true
    toolTipMainText: i18n("Applications")
    toolTipSubText: ""

    property Kicker.RootModel rootModel: Kicker.RootModel {
        autoPopulate: false
        appletInterface: menu
        flat: true
        sorted: true
        showSeparators: false
        showTopLevelItems: true
        // Row 0 is "All Applications", one alphabetical list.
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false

        Component.onCompleted: {
            const favorites = rootModel.favoritesModel;
            if (!favorites) {
                return;
            }
            favorites.initForClient("dev.flatkit.menu.favorites.instance-" + Plasmoid.id);
            if (!Plasmoid.configuration.favoritesSeeded) {
                favorites.portOldFavorites(Plasmoid.configuration.defaultFavorites);
                Plasmoid.configuration.favoritesSeeded = true;
            }
        }
    }

    property Kicker.RecentUsageModel recentModel: Kicker.RecentUsageModel {
        shownItems: Kicker.RecentUsageModel.OnlyApps
        ordering: Kicker.RecentUsageModel.Recent
    }

    // KRunner search: apps, settings, the calculator, files, commands.
    property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        appletInterface: menu
        favoritesModel: menu.rootModel.favoritesModel
        mergeResults: true
    }

    property Kicker.SystemModel systemModel: Kicker.SystemModel {
        favoritesModel: menu.rootModel.systemFavoritesModel
    }

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        activeFocusOnTab: true
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        onClicked: menu.expanded = !menu.expanded
        Keys.onReturnPressed: menu.expanded = !menu.expanded
        Keys.onSpacePressed: menu.expanded = !menu.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: compact.containsMouse || menu.expanded
        }
    }

    fullRepresentation: MenuView {
        menuItem: menu
        rootModel: menu.rootModel
        recentModel: menu.recentModel
        runnerModel: menu.runnerModel
        systemModel: menu.systemModel
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Edit Applications…")
            icon.name: "kmenuedit"
            visible: Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable
            onTriggered: processRunner.runMenuEditor()
        }
    ]

    Kicker.ProcessRunner {
        id: processRunner
    }

    Component.onCompleted: rootModel.refresh()
}
