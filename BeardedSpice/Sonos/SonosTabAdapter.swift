//
//  SonosTabAdapter.swift
//  Beardie
//
//  Created by Roman Sokolov on 02.07.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Cocoa
import RxSwift
import RxSonosLib

final class SonosTabAdapter: TabAdapter, BSVolumeControlProtocol {

    // MARK: Init
    
    init(_ group: Group) {
        self.group = group
        
        super.init()
        
        
        DDLogDebug("Init tab for group: \(group.name)")
    }
    
    // MARK: Public
    @objc var displayName: String {"\(self.group.name) Sonos"}
    
    // MARK: Overrides
    
    override var application: runningSBApplication! {
        runningSBApplication.sharedApplication(forBundleIdentifier: "com.sonos.macController2")
    }
    
    override func title() -> String! {
        let sync = DispatchGroup()
        var title: String?
        sync.enter()
        let subsrc = SonosInteractor.singleTrack(self.group)
            .debug()
            .subscribe { event in
                if case .success(let track) = event {
                    title = track?.title
                }
                sync.leave()
            }
        
        sync.wait()
        subsrc.dispose()
        
        if let title = title {
            return "\(self.displayName) | \(title)"
        }
        return "\(self.displayName)"
    }
    
    override func url() -> String! {
        return self.group.master.ip.absoluteString
    }
    override func key() -> String! {
        return self.group.slaves.reduce(self.group.master.uuid) { $0 + $1.uuid }
    }
    override func activateTab() -> Bool {
        self.wasActivated = true
        return self.wasActivated
    }
    override func deactivateTab() -> Bool {
        defer {
            self.wasActivated = false
        }
        return self.wasActivated && super.deactivateTab()
    }
    override func isActivated() -> Bool {
        return self.wasActivated && super.isActivated()
    }
    override func toggleTab() {
        
        let result = self.deactivateTab()
        if result {
            self.deactivateApp()
        }
        if !result {
            
            _ = self.activateApp()
            _ = self.activateTab()
        }
        
    }
    override func frontmost() -> Bool {
        super.frontmost() && wasActivated
    }
    
    override func toggle() -> Bool {
        self.switchState()
    }
    override func pause() -> Bool {
        self.switchState(onlyPause: true)
    }
    
    override func next() -> Bool {
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.setNextTrack(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                if case .completed = event { result = true }
                sync.leave()
            }
            .disposed(by: bag)
        
        sync.wait()
        
        self.needNoti = result && !self.isPlaying()

        return result
    }
    
    override func previous() -> Bool {
        
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.setPreviousTrack(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                if case .completed = event { result = true }
                sync.leave()
            }
            .disposed(by: bag)
        
        sync.wait()

        self.needNoti = result && !self.isPlaying()

        return result
    }
    
    override func isPlaying() -> Bool {
        var result = false
        let sync = DispatchGroup()
        sync.enter()
        let subscr = SonosInteractor.singleTransportState(self.group)
            .observeOn(self.queue)
            .subscribe {  event in
                switch event {
                case .success(let val):
                    result = val == .playing || val == .transitioning
                default:
                    result = false
                }
                sync.leave()
            }

        sync.wait()
        subscr.dispose()
        DDLogDebug("isPlaying result: \(result)")
        return result
    }
    
    override func showNotifications() -> Bool {
        defer {
            self.needNoti = true
        }
        return self.application == nil || self.needNoti
    }
    
    override func trackInfo() -> BSTrack! {
        var result: BSTrack! = BSTrack()
        let localBag = DisposeBag()
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleTrack(self.group)
            .observeOn(self.queue)
            .debug()
            .subscribe { [weak self] event in
                defer {
                    sync.leave()
                }
                guard let self = self else {return}
                DDLogDebug("Progress Event: \(event)")
                switch event {
                case .success(let track):
                    guard let track = track else {
                        result = nil
                        return
                    }
                    if let progress = track.progress, progress.duration > 0 {
                        result.progress = "\(progress.timeString) of \(progress.durationString)"
                    }
                    result.track = track.title
                    result.artist = track.artist
                    result.album = track.album
                    sync.enter()
                    SonosInteractor.singleImage(track)
                        .observeOn(self.queue)
                        .debug()
                        .subscribe { [weak self] event in
                            defer {
                                sync.leave()
                            }
                            guard let self = self else { return }
                            switch event {
                            case .success(let data):
                                result?.image = NSImage(data: data)
                            default:
                                result?.image = nil
                            }
                            DDLogDebug("Group (\(self.group.name)) image track: \(String(describing: result))")
                        }
                        .disposed(by: localBag)
                    
                default:
                    result = nil
                }
                DDLogDebug("Group (\(self.group.name)) track: \(String(describing: result))")
                
            }
            .disposed(by: localBag)
        
        sync.wait()
        
        return result
    }
    
    // MARK: BSVolumeControlProtocol Implementation
    
    func volumeUp() -> BSVolumeControlResult {
        return self.volumeAction(.up)
    }
    
    func volumeDown() -> BSVolumeControlResult {
        return self.volumeAction(.down)
    }
    func volumeMute() -> BSVolumeControlResult {

        let bag = DisposeBag()
        var result = BSVolumeControlResult.unavailable
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleMute(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                defer {
                    sync.leave()
                }
                switch event {
                case .success(let val):
                    sync.enter()
                    Observable<Group>.just(self.group)
                        .observeOn(self.queue)
                        .set(mute: !val)
                        .subscribe { event in
                            switch event {
                            case .completed:
                                result = val ? .unmute : .mute
                            default:
                                result = .unavailable
                            }
                            sync.leave()
                        }
                        .disposed(by: bag)
                default:
                    result = .unavailable
                }
            }
            .disposed(by: bag)
        
        sync.wait()
        return result
    }
    

    // MARK: Private Helper
    
    private let queue = SerialDispatchQueueScheduler(internalSerialQueueName: "SonosTabAdapterQueue")
    private let group: Group
    private var wasActivated = false
    private var needNoti = true
    
    private func switchState(onlyPause: Bool = false) -> Bool {
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.getTransportState(self.group)
            .first()
            .catchErrorJustReturn(nil)
            .map { (state) -> TransportState? in
                return (state ?? .stopped) == .playing ? .paused : state?.reverseState()
            }
            .asObservable()
            .asSingle()
            .observeOn(self.queue)
            .subscribe { [weak self] event in
                defer {
                    sync.leave()
                }
                guard let self = self else {return}
                if case .success(let state) = event {
                    if let state = state {
                       if state == .paused || !onlyPause {
                        sync.enter()
                        SonosInteractor.setTransport(state: state, for: self.group)
                            .observeOn(self.queue)
                            .subscribe { event in
                                if case .completed = event { result = true }
                                
                                self.needNoti = result && state == .paused

                                sync.leave()
                            }
                            .disposed(by: bag)
                       }
                       else { result = true }
                    }
                }
            }
            .disposed(by: bag)
        
        sync.wait()

        return result
    }
    private func volumeAction(_ direction: BSVolumeControlResult) -> BSVolumeControlResult {
        var action: (Int) -> Int = { $0 }
        var complated: (Int) -> BSVolumeControlResult = { _ in .unavailable }
        switch direction {
        case .up:
            action = { min($0 +  SonosRoomsController.sonosVolumeStep, SonosRoomsController.sonosMaxVolume) }
            complated = { $0 == SonosRoomsController.sonosMaxVolume ? .unavailable : .up}
        case .down:
            action = { max($0 -  SonosRoomsController.sonosVolumeStep, 0) }
            complated = {$0 == 0 ? .mute : .down}
        default:
            return .notSupported
        }
        
        let bag = DisposeBag()
        var result = BSVolumeControlResult.unavailable
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleVolume(self.group)
            .observeOn(self.queue)
            .subscribe {  event in
                defer {
                    sync.leave()
                }
                switch event {
                case .success(let val):
                    guard val < SonosRoomsController.sonosMaxVolume else {
                        return
                    }
                    sync.enter()
                    let newVal = action(val)
                    Observable<Group>.just(self.group)
                        .observeOn(self.queue)
                        .set(mute: false)
                        .andThen(SonosInteractor.change(volume: newVal,
                                                        for: self.group))
                        .subscribe { event in
                            if case .completed = event {
                                result = complated(newVal)
                            }
                            sync.leave()
                        }
                        .disposed(by: bag)
                default:
                    result = .unavailable
                }
            }
            .disposed(by: bag)
        sync.wait()
        DDLogDebug("Volume action result: \(result)")
        return result
    }
}