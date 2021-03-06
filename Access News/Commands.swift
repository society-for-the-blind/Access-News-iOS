//
//  Commands.swift
//  Access News
//
//  Created by Attila Gulyas on 8/29/18.
//  Copyright © 2018 Society for the Blind. All rights reserved.
//

import UIKit
import Firebase

struct Commands {

//    static let db = Database.database()
    static let dbref = Database.database().reference()
    static let auth = Auth.auth()

    static func submit
        ( publication:   String
        , recordingName: String
        , duration:      Float64
        , recordingURL:  URL
        )
    {
        let path         = "recordings/\(publication)/\(recordingName)"
        let recordingRef = Storage.storage().reference().child(path)
        let streamID     = self.createNewStreamID();

        let metadata = StorageMetadata()
        metadata.customMetadata =
            [ "publication": "\(publication)"
            , "reader":      "\(CommonDefaults.userID())"
            , "duration":    "\(duration)"
            , "stream_id":   streamID
            ]

        recordingRef.putFile(
            from:     recordingURL,
            metadata: metadata)
        {
            (completionMetadata, error) in

                // This may be left here by accident. The only place I could
                // find `bucket.dispatchGroup.enter()` is in RecordVC's
                // `exportArticle()`, but `leave()` is used upon successful
                // export.
                /* bucket.dispatchGroup.leave() */

                recordingRef.downloadURL { (url, error) in

                    guard let completionMetadata = completionMetadata else { return }
                    print("\n\nBUCKET: \(completionMetadata.bucket)")
                    print(CommonDefaults.userID())

                    guard let downloadURL = url else { return }
                    print("\(downloadURL)\n\n")

                    /* TODO:
                       Make deletion the users choice.
                    */
                    // try! FileManager.default.removeItem(at: articleURLToSubmit)

                    Commands.addRecording(
                        streamID:      streamID,
                        publication:   publication,
                        recordingName: recordingName,
                        duration:      duration)
                }
        }
    }

    /* No pun intended (but I would definitely do something like this
       on purpose).

       `seq` for sessions are reset in SessionStartViewController, for
       recordings, it is set when starting a new recording
       (i.e., in `RecordViewController.recordTapped`).

       Updated in `dispatchEvent` when storing an event in Firebase DB.
    */
    static var seqs: [String: Int] =
        [ Aggregates.recording.rawValue: 1
        , Aggregates.session.rawValue:   1
        ]

    /*  NOTE FOR FUTURE SELF

        `seqUpdater` was used to get the current `seq`uental number
        of the stream's state (i.e., the current user state) because
        sessions and recordings have been handled inside the "person"
        aggregate.

        Since then, sessions and recordings got their own aggregate
        that reference the user they belong to. This means that no
        updater is necessary because

            + sessions `seq`s would be maintained by the respective
              app, and when a session is ended explicitly (hitting the
              "End Session" button for example) then a new session
              will be started.

              When sessions end in an improper way (app is closed via
              forced shutdown etc.), the only difference is that there
              won't be an explicit "session_ended" event generated. This
              is not an issue as both are handled by the `updateSession`
              command and it is mostly just a nicety.

            + At this point (005381aaa0a3eae4dd374103c755ac8c8e1a96b2 + 1,
              that is commit containing this note) recordings are only
              submitted, therefore the emitted event only generates a
              new aggregate instance (or stream) with `seq` always 1.

              Maybe editing will be allowed later or adding extra metadata,
              but that would probably be handled by the app itself.

    static func seqUpdater() {
        /* Invoked in SessionStartViewController because it is certain
         at that point that a user is logged in and we have the user_id.
         */
    }
    */

    static func createNewStreamID() -> String {
        return self.dbref.childByAutoId().key!
    }

    static var sessionID = ""

    static func startSession() {

        self.sessionID = self.createNewStreamID()

        self.dispatchEvent(
            aggregate: Aggregates.session.rawValue,
            eventName: "session_started",
            payload:   ["seconds": 0],
            streamID:  self.sessionID
        )
    }

    static func updateSession(seconds: Int, done: Bool = false) {

        let eventName = done ? "session_ended" : "session_time_updated"

        self.dispatchEvent(
            aggregate:  Aggregates.session.rawValue,
            eventName: eventName,
            payload:
                [ "seconds": seconds
                ],
            streamID:  self.sessionID
        )

        if  done == true {
            self.sessionID = ""
        }
        /* Not a problem if app terminates abnormally and sessionID
           won't get cleared, because `startSession` will assign a
           brand new sessionID once the app is restarted and "Start
           Session" is tapped.
        */
    }

    static func addRecording(streamID: String, publication: String, recordingName: String, duration: Float64) {

        self.dispatchEvent(
            aggregate: Aggregates.recording.rawValue,
            eventName: "recording_added",
            payload:
                [ "publication": publication
                , "filename":    recordingName
                , "duration":    String(Int(duration))
                ],
            streamID:  streamID
        )
    }

    static func dispatchEvent(
        aggregate: String,
        eventName: String,
        payload:   [String: Any],
        streamID:  String
    ) {

        let seq = self.seqs[aggregate]!
        self.seqs[aggregate] = seq + 1

        let payloadWithUserID =
            payload.merging(["user_id": CommonDefaults.userID()]) { (k,_) in k }

        let event: [String: Any] =
            [ "aggregate":  aggregate
            , "event_name": eventName
            , "fields":     payloadWithUserID
            , "seq":        seq
            , "stream_id":  streamID
            , "version":    0
            , "timestamp":  ServerValue.timestamp()
            ]

        let pushRef = self.dbref.child("/event_store").childByAutoId()

        /* UPDATE: 18/9/20
           Removed commandsGroup DispatchGroup, because I couldn't find
           its original purpose and nothing was entering it, so there was
           no point in waiting for anything. Fingers crossed.
        */
        // TODO: Why does this has to be in a dispatchGroup again?
        pushRef.setValue(event)
    }
}
