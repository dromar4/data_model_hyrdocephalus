-- ============================================================
-- FHIR-aligned Postgres schema for the clinical admission form
-- One table per FHIR resource actually used. Coded fields use
-- CHECK constraints against FHIR-defined ValueSets where a
-- fixed set exists; free-text/coding pairs use a (code, system,
-- display, text) pattern so you keep both machine code and
-- human text, same as a FHIR CodeableConcept.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PATIENT IDENTIFIERS  (Patient.identifier — repeating)
-- ============================================================
CREATE TABLE patient_identifier (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    type_code       text NOT NULL CHECK (type_code IN (
                        'NI',   -- National identifier 
                        'PPN',  -- Passport number
                        'MR'    -- Medical record number 
                    )),
    system          text NOT NULL,   -- URI of the assigning authority, e.g.
                                      -- 'urn:oid:2.16.818.1.1' (example EG national ID OID)
                                      -- or 'http://passports.gov/<country>'
    value           text NOT NULL,   -- the actual ID/passport number
    country         text,            -- relevant for PPN — issuing country
    UNIQUE (patient_id, type_code, system)
);

-- ============================================================
-- PATIENT TELECOM  (Patient.telecom — repeating)
-- ============================================================
CREATE TABLE patient_telecom (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    system          text NOT NULL CHECK (system IN ('phone','fax','email','pager','url','sms')),
    value           text NOT NULL,
    use             text CHECK (use IN ('home','work','temp','old','mobile')) DEFAULT 'mobile',
    rank            integer          -- preferred order, 1 = primary
);

-- ------------------------------------------------------------
-- Reusable composite type for CodeableConcept-like fields
-- ------------------------------------------------------------
CREATE TYPE codeable_concept AS (
    code    text,   -- e.g. SNOMED/LOINC/ICD-10 code
    system  text,   -- code system URI, e.g. 'http://snomed.info/sct'
    display text,   -- human-readable label for the code
    text    text    -- free text if uncoded / additional narrative
);

-- ============================================================
-- PATIENT
-- ============================================================
CREATE TABLE patient (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    mrn                 text UNIQUE NOT NULL,               -- Patient.identifier
    family_name         text NOT NULL,
    given_name          text NOT NULL,
    birth_date          date NOT NULL,                      -- Patient.birthDate
    gender              text NOT NULL CHECK (gender IN ('male','female','other','unknown')),
    residency_address   text,
    nationality         text,
    marital_status_code text,                                -- v3 MaritalStatus code e.g. 'M','S','D','W'
    deceased_datetime   timestamptz,                          -- Patient.deceasedDateTime
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- Occupation / habits — small repeating Observation-like facts about the patient
-- that aren't tied to one encounter (kept encounter-scoped instead below,
-- since occupation/habits are usually captured at admission — see
-- observation_social_history).

-- ============================================================
-- PRACTITIONER
-- ============================================================
CREATE TABLE practitioner (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name   text NOT NULL,
    role_title  text,          -- e.g. "Attending", "Resident"
    license_no  text
);

-- ============================================================
-- ENCOUNTER  (one row per admission)
-- ============================================================
CREATE TABLE encounter (
    id                      uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id              uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    admission_datetime      timestamptz NOT NULL,             -- Encounter.period.start
    discharge_datetime      timestamptz,                       -- Encounter.period.end
    class                   text NOT NULL CHECK (class IN ('IMP','AMB')),  -- inpatient/ambulatory
    status                  text NOT NULL CHECK (
                                status IN ('planned','in-progress','finished','cancelled')
                            ),
    created_at              timestamptz NOT NULL DEFAULT now()
);

-- Encounter.participant (repeating treating physicians)
CREATE TABLE encounter_participant (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    practitioner_id uuid NOT NULL REFERENCES practitioner(id),
    participant_type text NOT NULL DEFAULT 'ATND'   -- attender, consultant, etc.
);

-- Encounter.statusHistory  — status logged with time (Inpatient / Outpatient /
-- Discharge-improved / Escape / DAMA / Deceased), append-only
CREATE TABLE encounter_status_history (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    status_code     text NOT NULL CHECK (status_code IN (
                        'inpatient',
                        'outpatient',
                        'discharged_improved',
                        'escape',
                        'discharge_ama',
                        'deceased'
                    )),
    logged_at       timestamptz NOT NULL DEFAULT now(),
    logged_by       uuid REFERENCES practitioner(id)
);

-- Encounter.hospitalization.dischargeDisposition (standard FHIR code where one exists)
CREATE TABLE encounter_discharge_disposition (
    encounter_id    uuid PRIMARY KEY REFERENCES encounter(id) ON DELETE CASCADE,
    disposition_code text NOT NULL CHECK (disposition_code IN (
                        'home','alt-home','aadvice','exp','other'  -- 'other' covers 'escape' (no FHIR core code)
                    )),
    disposition_note text
);

-- ============================================================
-- HISTORY
-- ============================================================

-- Chief complaint / onset text
CREATE TABLE chief_complaint (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    complaint_text  text NOT NULL,
    onset_text      text            -- "since ..." free text; use onset_date if parseable
);

-- History of present illness (narrative)
CREATE TABLE history_present_illness (
    encounter_id    uuid PRIMARY KEY REFERENCES encounter(id) ON DELETE CASCADE,
    narrative       text NOT NULL
);

-- Condition: past medical + surgical history, working/provisional/differential diagnoses
-- all live here, distinguished by category/verification_status (mirrors FHIR Condition)
CREATE TABLE condition (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id        uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    patient_id          uuid NOT NULL REFERENCES patient(id),
    category            text NOT NULL CHECK (category IN (
                            'past-medical-history',
                            'past-surgical-history',
                            'encounter-diagnosis'       -- working/provisional/differential live here
                        )),
    verification_status text CHECK (verification_status IN (
                            'confirmed','provisional','differential','refuted'
                        )),
    code                text,           -- ICD-10 / SNOMED code
    code_system         text,
    display             text,
    free_text           text,
    onset_text          text,
    recorded_at         timestamptz NOT NULL DEFAULT now()
);

-- Developmental history (optional) — kept as flexible key/value since no
-- standard code system fits well; jsonb lets you add milestones without migrations
CREATE TABLE developmental_history (
    encounter_id    uuid PRIMARY KEY REFERENCES encounter(id) ON DELETE CASCADE,
    milestones      jsonb           -- e.g. {"head_control_months": 4, "walking_months": 14}
);

-- Past investigations referenced at history-taking (pointer, not re-entry)
CREATE TABLE past_investigation_reference (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    description     text NOT NULL,
    date_performed  date,
    external_ref    text            -- link/accession number to prior report if available
);

-- FamilyMemberHistory
CREATE TABLE family_history (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    relationship    text NOT NULL,   -- e.g. 'mother','father','sibling'
    condition_text  text NOT NULL,
    condition_code  text,
    condition_system text
);

-- MedicationStatement (history) vs medication_request (active orders, see Treatment)
CREATE TABLE medication_statement (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    drug_text       text NOT NULL,
    drug_code       text,
    status          text CHECK (status IN ('active','completed','stopped','unknown')) DEFAULT 'unknown',
    dose_text       text
);

-- Social history (Observation, category=social-history) incl. occupation & habits
CREATE TABLE observation_social_history (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    obs_type        text NOT NULL,   -- 'occupation','habit_smoking','habit_alcohol','other'
    loinc_code      text,            -- e.g. 74165-2 occupation, 72166-2 smoking status
    value_text      text NOT NULL
);

-- Immunization (one row per vaccine event)
CREATE TABLE immunization (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    vaccine_code    text NOT NULL,
    vaccine_display text,
    occurrence_date date,
    status          text CHECK (status IN ('completed','not-done','entered-in-error')) DEFAULT 'completed'
);

-- ============================================================
-- EXAMINATION
-- ============================================================

CREATE TABLE examination (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id        uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    examined_at          timestamptz NOT NULL,
    examiner_id          uuid REFERENCES practitioner(id)
);

-- Vitals as structured Observations (one row per exam, columns for the fixed set
-- given in the form; add a units check if you need strict UCUM validation)
CREATE TABLE vitals (
    examination_id      uuid PRIMARY KEY REFERENCES examination(id) ON DELETE CASCADE,
    bp_systolic         integer,   -- LOINC 8480-6
    bp_diastolic        integer,   -- LOINC 8462-4
    heart_rate          integer,   -- LOINC 8867-4
    respiratory_rate    integer,   -- LOINC 9279-1
    pulse                integer,   -- LOINC 8867-4 (peripheral) — separate from HR if clinically distinct
    temperature_celsius  numeric(4,1)  -- LOINC 8310-5
);

-- Exam findings by system — one row per system per examination
CREATE TABLE examination_finding (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    examination_id  uuid NOT NULL REFERENCES examination(id) ON DELETE CASCADE,
    system          text NOT NULL CHECK (system IN (
                        'general','neurological','pulmonological','git',
                        'cardiac','genitourinary','psychological','musculoskeletal'
                    )),
    finding_text    text NOT NULL,
    UNIQUE (examination_id, system)
);

-- ============================================================
-- INTERVENTIONS / INVESTIGATIONS / TREATMENT
-- ============================================================

-- Procedure: bedside interventions with timing, and surgical treatment
CREATE TABLE procedure (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    category        text NOT NULL CHECK (category IN ('intervention','surgical-treatment')),
    procedure_text  text NOT NULL,
    procedure_code  text,
    performed_start timestamptz NOT NULL,
    performed_end   timestamptz,
    performed_by    uuid REFERENCES practitioner(id)
);

-- ServiceRequest — the order for any investigation
CREATE TABLE service_request (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    category        text NOT NULL CHECK (category IN ('lab','radiology','pathology')),
    requested_test  text NOT NULL,
    ordered_at      timestamptz NOT NULL DEFAULT now(),
    ordered_by      uuid REFERENCES practitioner(id)
);

-- DiagnosticReport — the result, linked back to the order
CREATE TABLE diagnostic_report (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_request_id  uuid REFERENCES service_request(id) ON DELETE SET NULL,
    encounter_id         uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    category             text NOT NULL CHECK (category IN ('lab','radiology','pathology')),
    conclusion            text,
    reported_at            timestamptz NOT NULL DEFAULT now()
);

-- Lab result components (Observation per analyte, LOINC-coded)
CREATE TABLE lab_result (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id uuid NOT NULL REFERENCES diagnostic_report(id) ON DELETE CASCADE,
    loinc_code           text NOT NULL,
    analyte_name          text NOT NULL,
    value_numeric          numeric,
    value_text              text,
    unit                     text,
    reference_range         text,
    abnormal_flag            text CHECK (abnormal_flag IN ('N','H','L','HH','LL','A') )
);

-- ImagingStudy — MRI/CT/US/X-Ray
CREATE TABLE imaging_study (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id uuid NOT NULL REFERENCES diagnostic_report(id) ON DELETE CASCADE,
    modality            text NOT NULL CHECK (modality IN ('MR','CT','US','CR')),  -- CR = plain X-ray, DICOM CID 29
    body_site            text,
    performed_at           timestamptz NOT NULL,
    image_ref               text        -- URL/path to stored image or PACS accession number
);

-- Pathology-specific: Specimen
CREATE TABLE specimen (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id uuid NOT NULL REFERENCES diagnostic_report(id) ON DELETE CASCADE,
    specimen_type        text NOT NULL,
    collected_at          timestamptz
);

-- MedicationRequest — active medical treatment orders
CREATE TABLE medication_request (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    drug_text       text NOT NULL,
    drug_code       text,
    dose_text       text,
    route           text,
    frequency       text,
    prescribed_by   uuid REFERENCES practitioner(id),
    prescribed_at   timestamptz NOT NULL DEFAULT now(),
    status          text CHECK (status IN ('active','completed','stopped','on-hold')) DEFAULT 'active'
);

-- ============================================================
-- COMPOSITION-LEVEL NOTES
-- ============================================================

CREATE TABLE additional_remarks (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    remark_text     text NOT NULL,
    authored_by     uuid REFERENCES practitioner(id),
    authored_at     timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- Helpful indexes
-- ============================================================
CREATE INDEX idx_encounter_patient        ON encounter(patient_id);
CREATE INDEX idx_condition_encounter       ON condition(encounter_id);
CREATE INDEX idx_condition_category        ON condition(category, verification_status);
CREATE INDEX idx_examination_encounter     ON examination(encounter_id);
CREATE INDEX idx_service_request_encounter ON service_request(encounter_id);
CREATE INDEX idx_diagnostic_report_encounter ON diagnostic_report(encounter_id);
CREATE INDEX idx_status_history_encounter  ON encounter_status_history(encounter_id, logged_at);
