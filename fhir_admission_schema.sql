-- ============================================================
-- FHIR-aligned Postgres schema for clinical admission
-- Supports: standard admissions, minors (guardian/proxy),
--           emergency/trauma (unidentified patients)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------
-- Reusable composite type for CodeableConcept-like fields
-- ------------------------------------------------------------
CREATE TYPE codeable_concept AS (
    code    text,
    system  text,
    display text,
    text    text
);

-- ============================================================
-- PATIENT
-- ============================================================
-- Name, birthDate, and gender are nullable to match FHIR
-- cardinality (0..* / 0..1) and to allow emergency "John Doe"
-- registrations where demographics are initially unknown.
-- ============================================================
CREATE TABLE patient (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    mrn                 text UNIQUE NOT NULL,
    family_name         text,
    given_name          text,
    birth_date          date,
    gender              text CHECK (gender IN ('male','female','other','unknown')),
    residency_address   text,
    nationality         text,
    marital_status_code text,
    deceased_datetime   timestamptz,
    is_unidentified          boolean DEFAULT false,
    unidentified_reception   timestamptz,
    estimated_age_min        integer,
    estimated_age_max        integer,
    emergency_notes          text,
    primary_guardian_id      uuid,  -- populated after patient_contact is created
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- PATIENT IDENTIFIER  (Patient.identifier)
-- ============================================================
CREATE TABLE patient_identifier (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    type_code       text NOT NULL CHECK (type_code IN (
                        'NI',
                        'PPN',
                        'MR',
                        'TEMP',
                        'UNKNOWN'
                    )),
    system          text NOT NULL,
    value           text NOT NULL,
    country         text,
    UNIQUE (patient_id, type_code, system)
);

-- ============================================================
-- PATIENT TELECOM  (Patient.telecom)
-- ============================================================
CREATE TABLE patient_telecom (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    system          text NOT NULL CHECK (system IN ('phone','fax','email','pager','url','sms')),
    value           text NOT NULL,
    use             text CHECK (use IN ('home','work','temp','old','mobile')) DEFAULT 'mobile',
    rank            integer
);

-- ============================================================
-- PRACTITIONER
-- ============================================================
CREATE TABLE practitioner (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name   text NOT NULL,
    role_title  text,
    license_no  text
);

-- ============================================================
-- PATIENT CONTACT  (Patient.contact / RelatedPerson)
-- Guardians, parents, next-of-kin, emergency contacts
-- ============================================================
CREATE TABLE patient_contact (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id           uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    relationship_code    text NOT NULL,
    relationship_system  text DEFAULT 'http://terminology.hl7.org/CodeSystem/v3-RoleCode',
    relationship_display text,
    full_name            text NOT NULL,
    telecom_system       text CHECK (telecom_system IN ('phone','fax','email','pager','url','sms')),
    telecom_value        text,
    telecom_use          text CHECK (telecom_use IN ('home','work','temp','old','mobile')),
    address              text,
    gender               text CHECK (gender IN ('male','female','other','unknown')),
    organization         text,
    period_start         date,
    period_end           date,
    is_emergency_contact boolean DEFAULT false,
    is_legal_guardian    boolean DEFAULT false,
    created_at           timestamptz NOT NULL DEFAULT now()
);

-- Link patient to primary guardian (optional denormalization)
ALTER TABLE patient ADD CONSTRAINT fk_patient_primary_guardian
    FOREIGN KEY (primary_guardian_id) REFERENCES patient_contact(id);

-- ============================================================
-- PATIENT LINK  (Patient.link)
-- Merges temporary unidentified records with real identity later
-- ============================================================
CREATE TABLE patient_link (
    id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_patient_id uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    target_patient_id uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    link_type         text NOT NULL CHECK (link_type IN ('replaced-by','replaces','refer','seealso')),
    created_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_patient_id, target_patient_id),
    CHECK (source_patient_id <> target_patient_id)
);

-- ============================================================
-- ENCOUNTER  (one row per admission)
-- ============================================================
CREATE TABLE encounter (
    id                      uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id              uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    admission_datetime      timestamptz NOT NULL,
    discharge_datetime      timestamptz,
    class                   text NOT NULL CHECK (class IN ('IMP','AMB','EMER')),
    status                  text NOT NULL CHECK (
                                status IN ('planned','in-progress','finished','cancelled')
                            ),
    priority                text CHECK (priority IN (
                                'routine','urgent','emergent','asap','stat'
                            )),
    reason_text             text,
    reason_code             text,
    reason_code_system      text,
    reason_display          text,
    arrival_mode            text CHECK (arrival_mode IN (
                                'ambulance','self_presented','police','transfer','other'
                            )),
    created_at              timestamptz NOT NULL DEFAULT now()
);

-- Encounter.participant
CREATE TABLE encounter_participant (
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id     uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    practitioner_id  uuid NOT NULL REFERENCES practitioner(id),
    participant_type text NOT NULL DEFAULT 'ATND'
);

-- Encounter.statusHistory
CREATE TABLE encounter_status_history (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    status_code     text NOT NULL CHECK (status_code IN (
                        'inpatient',
                        'outpatient',
                        'discharged_improved',
                        'escape',
                        'discharge_ama',
                        'deceased',
                        'emergency_triage',
                        'emergency_treatment',
                        'emergency_observation'
                    )),
    logged_at       timestamptz NOT NULL DEFAULT now(),
    logged_by       uuid REFERENCES practitioner(id)
);

-- Encounter.hospitalization.dischargeDisposition
CREATE TABLE encounter_discharge_disposition (
    encounter_id     uuid PRIMARY KEY REFERENCES encounter(id) ON DELETE CASCADE,
    disposition_code text NOT NULL CHECK (disposition_code IN (
                        'home','alt-home','aadvice','exp','other'
                    )),
    disposition_note text
);

-- ============================================================
-- CONSENT  (FHIR Consent — admission use)
-- Treatment consent, proxy/guardian consent for minors,
-- and emergency override when patient cannot consent.
-- ============================================================
CREATE TABLE consent (
    id                       uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id               uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    encounter_id             uuid REFERENCES encounter(id) ON DELETE CASCADE,
    status                   text NOT NULL CHECK (status IN (
                                 'draft','proposed','active','rejected',
                                 'inactive','entered-in-error'
                             )),
    scope_code               text NOT NULL DEFAULT 'treatment',
    scope_system             text DEFAULT 'http://terminology.hl7.org/CodeSystem/consentscope',
    category_code            text,
    category_system          text,
    category_display         text,
    consent_date             timestamptz NOT NULL DEFAULT now(),
    given_by_contact_id      uuid REFERENCES patient_contact(id),
    given_by_practitioner_id uuid REFERENCES practitioner(id),
    patient_self_consent     boolean DEFAULT false,
    source                   text CHECK (source IN (
                                 'written','verbal','implied',
                                 'emergency_override','court_order'
                             )),
    source_attachment_url    text,
    policy_uri               text,
    provision_type           text CHECK (provision_type IN ('permit','deny')) DEFAULT 'permit',
    provision_text           text NOT NULL,
    provision_period_start   timestamptz,
    provision_period_end     timestamptz,
    is_proxy_consent         boolean DEFAULT false,
    is_emergency_override    boolean DEFAULT false,
    emergency_override_reason text,
    created_at               timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- HISTORY
-- ============================================================

CREATE TABLE chief_complaint (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    complaint_text  text NOT NULL,
    onset_text      text
);

CREATE TABLE history_present_illness (
    encounter_id    uuid PRIMARY KEY REFERENCES encounter(id) ON DELETE CASCADE,
    narrative       text NOT NULL
);

CREATE TABLE condition (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id        uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    patient_id          uuid NOT NULL REFERENCES patient(id),
    category            text NOT NULL CHECK (category IN (
                            'past-medical-history',
                            'past-surgical-history',
                            'encounter-diagnosis'
                        )),
    verification_status text CHECK (verification_status IN (
                            'confirmed','provisional','differential','refuted'
                        )),
    code                text,
    code_system         text,
    display             text,
    free_text           text,
    onset_text          text,
    recorded_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE developmental_history (
    encounter_id    uuid PRIMARY KEY REFERENCES encounter(id) ON DELETE CASCADE,
    milestones      jsonb
);

CREATE TABLE past_investigation_reference (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    description     text NOT NULL,
    date_performed  date,
    external_ref    text
);

CREATE TABLE family_history (
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id     uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    relationship     text NOT NULL,
    condition_text   text NOT NULL,
    condition_code   text,
    condition_system text
);

CREATE TABLE medication_statement (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    drug_text       text NOT NULL,
    drug_code       text,
    status          text CHECK (status IN ('active','completed','stopped','unknown')) DEFAULT 'unknown',
    dose_text       text
);

CREATE TABLE observation_social_history (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    obs_type        text NOT NULL,
    loinc_code      text,
    value_text      text NOT NULL
);

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
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    examined_at     timestamptz NOT NULL,
    examiner_id     uuid REFERENCES practitioner(id)
);

CREATE TABLE vitals (
    examination_id      uuid PRIMARY KEY REFERENCES examination(id) ON DELETE CASCADE,
    bp_systolic         integer,
    bp_diastolic        integer,
    heart_rate          integer,
    respiratory_rate    integer,
    pulse               integer,
    temperature_celsius numeric(4,1)
);

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

CREATE TABLE service_request (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    category        text NOT NULL CHECK (category IN ('lab','radiology','pathology')),
    requested_test  text NOT NULL,
    ordered_at      timestamptz NOT NULL DEFAULT now(),
    ordered_by      uuid REFERENCES practitioner(id)
);

CREATE TABLE diagnostic_report (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_request_id   uuid REFERENCES service_request(id) ON DELETE SET NULL,
    encounter_id         uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    category             text NOT NULL CHECK (category IN ('lab','radiology','pathology')),
    conclusion           text,
    reported_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE lab_result (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id uuid NOT NULL REFERENCES diagnostic_report(id) ON DELETE CASCADE,
    loinc_code           text NOT NULL,
    analyte_name         text NOT NULL,
    value_numeric        numeric,
    value_text           text,
    unit                 text,
    reference_range      text,
    abnormal_flag        text CHECK (abnormal_flag IN ('N','H','L','HH','LL','A'))
);

CREATE TABLE imaging_study (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id uuid NOT NULL REFERENCES diagnostic_report(id) ON DELETE CASCADE,
    modality             text NOT NULL CHECK (modality IN ('MR','CT','US','CR')),
    body_site            text,
    performed_at         timestamptz NOT NULL,
    image_ref            text
);

CREATE TABLE specimen (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id uuid NOT NULL REFERENCES diagnostic_report(id) ON DELETE CASCADE,
    specimen_type        text NOT NULL,
    collected_at         timestamptz
);

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
-- INDEXES
-- ============================================================

-- Original indexes
CREATE INDEX idx_encounter_patient              ON encounter(patient_id);
CREATE INDEX idx_condition_encounter            ON condition(encounter_id);
CREATE INDEX idx_condition_category             ON condition(category, verification_status);
CREATE INDEX idx_examination_encounter          ON examination(encounter_id);
CREATE INDEX idx_service_request_encounter      ON service_request(encounter_id);
CREATE INDEX idx_diagnostic_report_encounter    ON diagnostic_report(encounter_id);
CREATE INDEX idx_status_history_encounter       ON encounter_status_history(encounter_id, logged_at);

-- New indexes for minors / emergency features
CREATE INDEX idx_patient_contact_patient        ON patient_contact(patient_id);
CREATE INDEX idx_patient_contact_guardian       ON patient_contact(patient_id, is_legal_guardian) WHERE is_legal_guardian = true;
CREATE INDEX idx_patient_contact_emergency      ON patient_contact(patient_id, is_emergency_contact) WHERE is_emergency_contact = true;
CREATE INDEX idx_consent_patient                ON consent(patient_id);
CREATE INDEX idx_consent_encounter              ON consent(encounter_id);
CREATE INDEX idx_patient_link_source            ON patient_link(source_patient_id);
CREATE INDEX idx_patient_link_target            ON patient_link(target_patient_id);
CREATE INDEX idx_patient_unidentified           ON patient(is_unidentified) WHERE is_unidentified = true;
