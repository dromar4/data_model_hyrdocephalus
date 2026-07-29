# FHIR Data Model — Clinical Admission Form

Mapping of each form field to FHIR R4 resources. Each section lists: **Resource**, key **elements used**, and **binding/terminology** notes.

---

## 1. Administrative Block

| Field | FHIR Resource.Element |
|---|---|
| Patient number | `Patient.identifier` (type = MR, system = local MRN OID) |
| Date of Admission | `Encounter.period.start` |
| Treating physician(s) | `Encounter.participant.individual` → `Practitioner` (participant.type = ATND/attender), multiple allowed via repeating `participant` |
| Name | `Patient.name.given` / `.family` |
| DOB | `Patient.birthDate` |
| Sex | `Patient.gender` (administrative-gender: male/female/other/unknown) |
| Residency and nationality | `Patient.address` (residency) + `Patient.extension` using `patient-nationality` extension (http://hl7.org/fhir/StructureDefinition/patient-nationality) |
| Occupation | `Observation` (LOINC 74165-2 "History of Occupation") or `PractitionerRole`-style extension; most implementations use `Observation` |
| Marital Status | `Patient.maritalStatus` (v3 MaritalStatus ValueSet) |
| Habits of medical importance | `Observation` (social-history category) — one per habit (smoking LOINC 72166-2, alcohol 74013-4, etc.) |

---

## 2. History

| Field | FHIR Resource |
|---|---|
| Complaint (chief complaint) | `Condition` with `Condition.category` = "chief-complaint" (custom/local, since there's no core CC resource) — **or** `Observation` LOINC 8661-1 "Chief complaint". Onset text ("Increasing head size since...") → `Condition.onset[x]` (onsetString or onsetDateTime) |
| History of present illness | `ClinicalImpression.description`, or `Composition.section` (narrative), or `DocumentReference` if kept as free text |
| Past medical/surgical history | `Condition` (category=problem-list-item, verificationStatus=confirmed) for medical; `Procedure` for surgical history |
| Developmental history | `Observation` (category=survey), custom local codes — no strong FHIR core code for pediatric developmental milestones outside profiles like **US Core Pediatric BMI/vitals**; use local CodeSystem |
| Past investigations | `DiagnosticReport` / `Observation` (dated in the past, referenced not re-entered) |
| Family history | `FamilyMemberHistory` |
| Drug history | `MedicationStatement` (status=completed/stopped, for history) vs `MedicationRequest` (for active orders, see Treatment section) |
| Social history | `Observation` (category=social-history), e.g. smoking status LOINC 72166-2 |
| Immunization history | `Immunization` (one resource per vaccine event) |

---

## 3. Examination

| Field | FHIR Resource |
|---|---|
| Time of examination | `Encounter.participant.period` or a dedicated `Observation.effectiveDateTime` shared by all exam Observations |
| BP | `Observation` LOINC 85354-9 (panel) with components 8480-6 (systolic) / 8462-4 (diastolic) |
| HR | `Observation` LOINC 8867-4 |
| RR | `Observation` LOINC 9279-1 |
| Pulse | `Observation` LOINC 8867-4 (same as HR if peripheral pulse rate) or 78564-5 for volume/character notes as component |
| Temp | `Observation` LOINC 8310-5 |
| General examination findings (open text) | `Observation` LOINC 8716-3 "Vital signs / general appearance" or `ClinicalImpression.finding`; free text goes in `Observation.valueString` or `.note` |
| Neurological / Pulmonological / GIT / Cardiac / Genitourinary / Psychological / Musculoskeletal findings | Each a separate `Observation` (category=exam), `Observation.bodySite` = relevant SNOMED body structure, `code` = system-specific exam LOINC/SNOMED (e.g. Neuro exam LOINC 34117-2 as a panel), `valueString`/`note` for free text |

All exam Observations share `Observation.encounter` reference and `Observation.effectiveDateTime` = time of examination.

---

## 4. Interventions, Investigations, Treatment

| Field | FHIR Resource |
|---|---|
| Interventions with timings | `Procedure` (procedure.performedDateTime/Period) — covers bedside interventions, not just OR procedures |
| Investigations (parent grouping) | `ServiceRequest` (the order) → `DiagnosticReport` / `Observation` (the result) |
| Labs | `DiagnosticReport` (category=LAB) containing `Observation` per analyte (LOINC-coded) |
| Radiology (parent) | `DiagnosticReport` (category=RAD) |
| MRI / CT / US / X-Ray | Each a `ImagingStudy` (modality coded DICOM CID 29 — MR/CT/US/CR) linked to a `DiagnosticReport`; report text in `DiagnosticReport.conclusion`, images referenced via `ImagingStudy.series` |
| Pathology | `DiagnosticReport` (category=PAT), with `Specimen` resource for the tissue/sample |
| Treatment – Medical | `MedicationRequest` (active orders) |
| Treatment – Surgical | `Procedure` (status=in-progress/completed, category=surgical procedure) |

---

## 5. Diagnosis

| Field | FHIR Resource |
|---|---|
| Working / Provisional diagnosis | `Condition.verificationStatus` = "provisional", `Condition.category` = "encounter-diagnosis" |
| Differential diagnosis | `Condition.verificationStatus` = "differential" — one `Condition` resource per candidate diagnosis, all linked to the same `Encounter` |

`Condition.code` uses ICD-10/SNOMED CT. For this case (increasing head size), the working diagnosis would code to something like SNOMED 253148002 (Hydrocephalus) as the leading Condition, with differentials as separate Condition resources.

---

## 6. Status and Notes

| Field | FHIR Resource |
|---|---|
| Patient status (Inpatient/Outpatient/Discharge-improved/Escape/DAMA/Deceased), logged with time | `Encounter.status` + `Encounter.statusHistory` (each entry has status + period, giving you the time-logged trail) — plus `Encounter.hospitalization.dischargeDisposition` for the discharge-type codes (home, AMA, expired, etc., using the `discharge-disposition` ValueSet) |
| Additional remarks | `Composition.section` (free text) or `Encounter.note` |

**Status code mapping:**
- Inpatient → `Encounter.class` = IMP, `status` = in-progress
- Outpatient → `Encounter.class` = AMB, `status` = in-progress/finished
- Discharge due to improvement → `status` = finished, `hospitalization.dischargeDisposition` = "home" (or "alt-home")
- Escape → `status` = finished, `dischargeDisposition` = local extension code (no standard FHIR code for "escaped/absconded" — needs a local CodeSystem entry, since core `discharge-disposition` doesn't cover this)
- Discharge Against Medical Advice → `dischargeDisposition` = "aadvice"
- Deceased → `status` = finished, `dischargeDisposition` = "exp", and `Patient.deceasedDateTime` set

---

## 7. Composition (ties the whole encounter note together)

A `Composition` resource (or `DocumentReference` if you just want the whole note as a blob) ties everything to one clinical document:

```
Composition
├── subject → Patient
├── encounter → Encounter
├── author → Practitioner(s)
├── section: History
├── section: Examination
├── section: Investigations
├── section: Treatment
├── section: Diagnosis
└── section: Additional Notes
```

---

## Notes on gaps / design decisions worth flagging

1. **No native FHIR resource for "chief complaint" or "escape/absconded" discharge** — both need local extensions/CodeSystems. Don't pretend these map cleanly; they don't, and any FHIR-compliance claim should note the extensions used.
2. **Developmental history** has no strong core resource — you'll be building a local Observation profile, not using an existing IG unless you adopt something like the pediatric FHIR IG.
3. **Free-text fields** (General Examination, HPI, Additional Remarks) are the weak point of "structured FHIR" — they're valid FHIR (as `valueString`/`.note`/`.text`) but give you none of the queryability that's presumably the point of structuring this at all. If Daoval's goal is analytics/interoperability rather than just digitizing the paper form, these are the fields to push toward structured Observations/coded values later, not just accept as free text permanently.
4. Every clinical resource above should carry `.subject` → Patient and `.encounter` → Encounter references to keep the graph queryable.

If useful, I can also produce an example JSON bundle instantiating this for the given patient (Mohamed Aly Mohamed Ahmed) as a concrete reference.
