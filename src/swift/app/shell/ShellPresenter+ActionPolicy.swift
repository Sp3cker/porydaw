extension ShellPresenter {
    func isActionEnabled(id: String, workspaceLoaded: Bool) -> Bool {
        guard sceneActive, let action = ShellActionCatalog.byId[id] else { return false }
        if session.wavExportPresenter().active { return false }
        if id == "view.polyphony_debugger" || id == "edit.preferences"
            || id == "edit.engine_settings"
        {
            return true
        }
        if id == "eventlist.move_up" || id == "eventlist.move_down" {
            guard session.songOpen else { return false }
            let events = session.eventListPresenter()
            guard events.attached, events.visible, !events.editing, !events.menuOpen else {
                return false
            }
            return events.model.row(at: events.currentRow)?.eventIndex != nil
        }
        if let command = action.command {
            return session.songOpen && session.gridCommandAvailable(command: command.rawValue)
        }
        switch id {
        case "songs.find": return session.projectOpen && workspaceLoaded
        case "file.new_song": return session.projectOpen
        case "file.import_midi": return session.projectOpen
        case "tools.import_sample": return session.projectOpen && !session.sampleStudio().editorOpen
        case "file.save_song": return session.songOpen && !session.saveInProgress
        case "file.register_song":
            return session.songOpen
                && session.songDockController().selectedTabRegistrationPending()
        case "file.close_tab": return session.songTabs.selectedPage != nil
        case "file.export_wav": return session.wavExportPresenter().exportAvailable
        case "edit.undo": return session.songOpen && session.canUndo
        case "edit.redo": return session.songOpen && session.canRedo
        case "edit.song_settings": return session.songOpen
        case "transport.follow_playhead", "transport.resonance":
            return true
        case "transport.go_to_start", "transport.play_pause":
            return session.songOpen && session.transportBarPresenter().state != 0
        case "transport.play":
            let state = session.transportBarPresenter().state
            return session.songOpen && state > 0 && state != 3
        case "transport.pause":
            return session.songOpen && session.transportBarPresenter().state == 3
        case "transport.stop":
            return session.songOpen && session.transportBarPresenter().state > 1
        case "transport.loop":
            return session.songOpen && session.transportBarPresenter().state != 0
        case "view.event_list":
            return session.songTabs.selectedPage != nil
        case "view.automation_drawer", "view.velocity_drawer", "view.voice_changes_drawer":
            return session.songTabs.selectedPage != nil && !session.songTabs.selectedTabShowsEvents
        default: return true  // open project and quit were always enabled
        }
    }

    func isActionCheckable(id: String) -> Bool {
        switch id {
        case "view.event_list", "view.automation_drawer", "view.velocity_drawer",
            "view.voice_changes_drawer", "view.polyphony_debugger",
            "view.note_names", "transport.loop",
            "transport.follow_playhead", "transport.resonance":
            return true
        default: return false
        }
    }

    func isActionChecked(id: String) -> Bool {
        switch id {
        case "view.event_list": return session.songTabs.selectedTabShowsEvents
        case "view.automation_drawer":
            return session.songTabs.selectedPage?.drawerPresenter().automationSection.visible ?? false
        case "view.velocity_drawer":
            return session.songTabs.selectedPage?.drawerPresenter().velocitySection.visible ?? false
        case "view.voice_changes_drawer":
            return session.songTabs.selectedPage?.drawerPresenter().voiceChangesSection.visible ?? false
        case "view.polyphony_debugger": return polyphonyVisible
        case "view.note_names": return session.noteNameMode
        case "transport.loop": return session.transportBarPresenter().loopEnabled
        case "transport.follow_playhead": return session.transportBarPresenter().followPlayhead
        case "transport.resonance": return session.transportBarPresenter().resonanceSuppression
        default: return false
        }
    }
}
