CarePlan ⟷ CareKit
===================

Testing app to work with FHIR `CarePlan` in a CareKit app.
Created during the [FHIR Connectathon #12](http://wiki.hl7.org/index.php?title=FHIR_Connectathon_12) in Montréal in the _Workflow_ track.


Workflow
========

Goal: patient performs an activity (getting a lab test done) found in his care plan.

- `CarePlan` is created/maintained by his care team, hosted on server X
- Phone reads `CarePlan` from X
    + Resolves subject
    + Resolves participant.member list
    + Resolves activity.reference list
    + Creates a note for the patient for every `DiagnosticOrder` it finds
    + When the patient marks the note as completed, creates a `Task` and sends it to Grahame's server
	+ Polls the order's status until its status is _completed_
- Lab polls for `Task` it can process on Grahame's server
    + Finds `Task` and pulls out `DiagnosticOrder` 
    + Lab acts on order and marks `DiagnosticOrder` as _InProgress_
    + Lab produces final `DiagnosticReport` and uploads
    + Lab marks `DiagnosticOrder` as _completed_
    + Lab creates `Task` for report review containing a link to `DiagnosticReport`   
