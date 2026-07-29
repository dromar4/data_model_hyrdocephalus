-- ============================================================
-- FHIR R4-Aligned Postgres Clinical Schema
-- Basic compliance layer: meta, text, extensions + proper datatypes
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PATIENT  (FHIR Resource: Patient)
-- ============================================================
CREATE TABLE patient (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Patient',

    -- FHIR Resource.meta (mandatory: versionId + lastUpdated)
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',

    -- FHIR Resource.text (narrative)
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,

    -- FHIR Resource.extension
    extensions          jsonb DEFAULT '[]',
    language            text,

    -- FHIR Patient fields
    active              boolean DEFAULT true,
    birth_date          date,
    gender              text CHECK (gender IN ('male','female','other','unknown')),
    deceased_boolean    boolean,
    deceased_datetime   timestamptz,
    marital_status_cc   jsonb,          -- CodeableConcept
    multiple_birth_boolean boolean,
    multiple_birth_integer integer,

    -- Local admission / emergency extensions
    mrn                 text UNIQUE,
    nationality         text,
    is_unidentified          boolean DEFAULT false,
    unidentified_reception   timestamptz,
    estimated_age_min        integer,
    estimated_age_max        integer,
    emergency_notes          text,
    primary_guardian_id      uuid,

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- PATIENT NAME  (FHIR HumanName)
-- ------------------------------------------------------------
CREATE TABLE patient_name (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    "use"           text CHECK ("use" IN ('usual','official','temp','nickname','anonymous','old','maiden')),
    text            text,
    family          text,
    given           text[],
    prefix          text[],
    suffix          text[],
    period_start    date,
    period_end      date
);

-- ------------------------------------------------------------
-- PATIENT ADDRESS  (FHIR Address)
-- ------------------------------------------------------------
CREATE TABLE patient_address (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    "use"           text CHECK ("use" IN ('home','work','temp','old','billing')),
    "type"          text CHECK ("type" IN ('postal','physical','both')),
    text            text,
    line            text[],
    city            text,
    district        text,
    state           text,
    postal_code     text,
    country         text,
    period_start    date,
    period_end      date
);

-- ------------------------------------------------------------
-- PATIENT IDENTIFIER  (FHIR Identifier)
-- ------------------------------------------------------------
CREATE TABLE patient_identifier (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id          uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    "use"               text CHECK ("use" IN ('usual','official','temp','secondary','old')),
    type_cc             jsonb,      -- CodeableConcept (Identifier Type)
    system              text NOT NULL,
    value               text NOT NULL,
    period_start        date,
    period_end          date,
    assigner_display    text,
    assigner_reference  text,
    UNIQUE (patient_id, system, value)
);

-- ------------------------------------------------------------
-- PATIENT TELECOM  (FHIR ContactPoint)
-- ------------------------------------------------------------
CREATE TABLE patient_telecom (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    "system"        text CHECK ("system" IN ('phone','fax','email','pager','url','sms')),
    value           text,
    "use"           text CHECK ("use" IN ('home','work','temp','old','mobile')),
    rank            integer,
    period_start    date,
    period_end      date
);

-- ------------------------------------------------------------
-- PATIENT CONTACT  (FHIR Patient.contact)
-- ------------------------------------------------------------
CREATE TABLE patient_contact (
    id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id           uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    relationship_cc      jsonb DEFAULT '[]',  -- CodeableConcept[]
    name                 jsonb,               -- HumanName
    telecom              jsonb DEFAULT '[]',  -- ContactPoint[]
    address              jsonb,               -- Address
    gender               text CHECK (gender IN ('male','female','other','unknown')),
    organization_id      uuid,
    organization_display text,
    period_start         date,
    period_end           date,
    is_emergency_contact boolean DEFAULT false,
    is_legal_guardian    boolean DEFAULT false,
    created_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE patient
    ADD CONSTRAINT fk_patient_primary_guardian
    FOREIGN KEY (primary_guardian_id) REFERENCES patient_contact(id);

-- ------------------------------------------------------------
-- PATIENT LINK  (FHIR Patient.link)
-- ------------------------------------------------------------
CREATE TABLE patient_link (
    id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id        uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    other_patient_id  uuid NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    link_type         text NOT NULL CHECK (link_type IN ('replaced-by','replaces','refer','seealso')),
    created_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (patient_id, other_patient_id),
    CHECK (patient_id <> other_patient_id)
);

-- ============================================================
-- PRACTITIONER  (FHIR Resource: Practitioner)
-- ============================================================
CREATE TABLE practitioner (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Practitioner',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,
    active              boolean DEFAULT true,
    birth_date          date,
    gender              text CHECK (gender IN ('male','female','other','unknown')),
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE practitioner_name (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    practitioner_id uuid NOT NULL REFERENCES practitioner(id) ON DELETE CASCADE,
    "use"           text CHECK ("use" IN ('usual','official','temp','nickname','anonymous','old','maiden')),
    text            text,
    family          text,
    given           text[],
    prefix          text[],
    suffix          text[],
    period_start    date,
    period_end      date
);

-- ============================================================
-- ENCOUNTER  (FHIR Resource: Encounter)
-- ============================================================
CREATE TABLE encounter (
    id                      uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type           text NOT NULL DEFAULT 'Encounter',
    meta_version_id         text,
    meta_last_updated       timestamptz,
    meta_profile            text[],
    meta_security           jsonb DEFAULT '[]',
    meta_tag                jsonb DEFAULT '[]',
    text_status             text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div                text,
    extensions              jsonb DEFAULT '[]',
    language                text,

    identifier              jsonb DEFAULT '[]',
    status                  text NOT NULL CHECK (status IN ('planned','arrived','triaged','in-progress','onleave','finished','cancelled')),
    class_cc                jsonb NOT NULL,          -- Coding / CodeableConcept
    type_cc                 jsonb DEFAULT '[]',     -- CodeableConcept[]
    serviceType_cc          jsonb,
    priority_cc             jsonb,
    subject_id              uuid NOT NULL REFERENCES patient(id),
    subject_display         text,
    episodeOfCare           jsonb DEFAULT '[]',
    basedOn                 jsonb DEFAULT '[]',
    appointment             jsonb DEFAULT '[]',
    period_start            timestamptz NOT NULL,
    period_end              timestamptz,
    "length"                interval,
    reasonCode_cc           jsonb DEFAULT '[]',
    reasonReference         jsonb DEFAULT '[]',
    diagnosis               jsonb DEFAULT '[]',     -- backbone element array
    account                 jsonb DEFAULT '[]',

    -- hospitalization backbone element (flattened key fields)
    hospitalization_admitSource_cc          jsonb,
    hospitalization_dischargeDisposition_cc jsonb,
    hospitalization_origin                  jsonb,  -- Reference
    hospitalization_destination             jsonb,  -- Reference
    hospitalization_dietPreference_cc       jsonb DEFAULT '[]',
    hospitalization_specialCourtesy_cc      jsonb DEFAULT '[]',
    hospitalization_specialArrangement_cc   jsonb DEFAULT '[]',

    location                jsonb DEFAULT '[]',
    serviceProvider_id      uuid REFERENCES practitioner(id),
    serviceProvider_display text,
    partOf_id               uuid REFERENCES encounter(id),
    partOf_display          text,

    -- Local extensions
    arrival_mode            text CHECK (arrival_mode IN ('ambulance','self_presented','police','transfer','other')),
    created_at              timestamptz NOT NULL DEFAULT now()
);

-- Encounter.participant (backbone element)
CREATE TABLE encounter_participant (
    id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id      uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    type_cc           jsonb DEFAULT '[]',
    period_start      timestamptz,
    period_end        timestamptz,
    individual_id     uuid REFERENCES practitioner(id),
    individual_type   text DEFAULT 'Practitioner',
    individual_display text
);

-- Encounter.statusHistory (backbone element)
CREATE TABLE encounter_status_history (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    encounter_id    uuid NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    status          text NOT NULL,
    period_start    timestamptz NOT NULL,
    period_end      timestamptz,
    logged_by       uuid REFERENCES practitioner(id)
);

-- ============================================================
-- CONDITION  (FHIR Resource: Condition)
-- ============================================================
CREATE TABLE condition (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Condition',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    clinicalStatus_cc   jsonb,
    verificationStatus_cc jsonb,
    category_cc         jsonb DEFAULT '[]',
    severity_cc         jsonb,
    code_cc             jsonb,
    bodySite_cc         jsonb DEFAULT '[]',
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid NOT NULL REFERENCES encounter(id),
    encounter_display   text,
    onsetDateTime       timestamptz,
    onsetAge            jsonb,
    onsetString         text,
    onsetPeriod         jsonb,
    onsetRange          jsonb,
    abatementDateTime   timestamptz,
    abatementAge        jsonb,
    abatementString     text,
    abatementPeriod     jsonb,
    abatementRange      jsonb,
    recordedDate        timestamptz,
    recorder_id         uuid REFERENCES practitioner(id),
    recorder_display    text,
    asserter_id         uuid REFERENCES practitioner(id),
    asserter_display    text,
    stage               jsonb DEFAULT '[]',
    evidence            jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',

    -- Local convenience (narrative fallback)
    free_text           text,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- OBSERVATION  (FHIR Resource: Observation)
-- Replaces: vitals, exam findings, social history, developmental history, lab results
-- ============================================================
CREATE TABLE observation (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Observation',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    basedOn             jsonb DEFAULT '[]',
    partOf              jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('registered','preliminary','final','amended','corrected','cancelled','entered-in-error','unknown')),
    category_cc         jsonb DEFAULT '[]',
    code_cc             jsonb NOT NULL,
    subject_id          uuid REFERENCES patient(id),
    subject_display     text,
    focus               jsonb DEFAULT '[]',
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    effectiveDateTime   timestamptz,
    effectivePeriod     jsonb,
    effectiveTiming     jsonb,
    effectiveInstant    timestamptz,
    issued              timestamptz,
    performer           jsonb DEFAULT '[]',
    valueQuantity       jsonb,
    valueCodeableConcept_cc jsonb,
    valueString         text,
    valueBoolean        boolean,
    valueInteger        integer,
    valueRange          jsonb,
    valueRatio          jsonb,
    valueSampledData    jsonb,
    valueTime           time,
    valueDateTime       timestamptz,
    valuePeriod         jsonb,
    dataAbsentReason_cc jsonb,
    interpretation_cc   jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    bodySite_cc         jsonb,
    method_cc           jsonb,
    specimen            jsonb,
    device              jsonb,
    referenceRange      jsonb DEFAULT '[]',
    hasMember           jsonb DEFAULT '[]',
    derivedFrom         jsonb DEFAULT '[]',
    component           jsonb DEFAULT '[]',

    -- Local linking
    diagnostic_report_id uuid,
    created_at           timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- CLINICAL IMPRESSION  (FHIR Resource: ClinicalImpression)
-- Replaces: examination entity, chief complaint narrative, additional remarks
-- ============================================================
CREATE TABLE clinical_impression (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'ClinicalImpression',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('draft','active','retired','entered-in-error')),
    statusReason_cc     jsonb,
    code_cc             jsonb,
    description         text,
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    effectiveDateTime   timestamptz,
    effectivePeriod     jsonb,
    date                timestamptz,
    assessor_id         uuid REFERENCES practitioner(id),
    assessor_display    text,
    previous            jsonb,
    problem             jsonb DEFAULT '[]',
    investigation       jsonb DEFAULT '[]',
    protocol            text[],
    summary             text,
    finding             jsonb DEFAULT '[]',
    prognosisCodeableConcept_cc jsonb DEFAULT '[]',
    prognosisReference  jsonb DEFAULT '[]',
    supportingInfo      jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- FAMILY MEMBER HISTORY  (FHIR Resource: FamilyMemberHistory)
-- ============================================================
CREATE TABLE family_member_history (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'FamilyMemberHistory',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    instantiatesCanonical text[],
    instantiatesUri     text[],
    status              text NOT NULL CHECK (status IN ('partial','completed','entered-in-error','health-unknown')),
    patient_id          uuid NOT NULL REFERENCES patient(id),
    patient_display     text,
    date                timestamptz,
    name                text,
    relationship_cc     jsonb NOT NULL,
    sex_cc              jsonb,
    bornPeriod          jsonb,
    bornDate            date,
    bornString          text,
    ageAge              jsonb,
    ageRange            jsonb,
    ageString           text,
    estimatedAge        boolean,
    deceasedBoolean     boolean,
    deceasedAge         jsonb,
    deceasedRange       jsonb,
    deceasedDate        date,
    deceasedString      text,
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    condition           jsonb DEFAULT '[]',

    encounter_id        uuid REFERENCES encounter(id),
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- IMMUNIZATION  (FHIR Resource: Immunization)
-- ============================================================
CREATE TABLE immunization (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Immunization',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('completed','entered-in-error','not-done')),
    statusReason_cc     jsonb,
    vaccineCode_cc      jsonb NOT NULL,
    patient_id          uuid NOT NULL REFERENCES patient(id),
    patient_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    occurrenceDateTime  timestamptz,
    occurrenceString    text,
    recorded            timestamptz,
    primarySource       boolean,
    reportOrigin_cc     jsonb,
    location            jsonb,
    manufacturer        jsonb,
    lotNumber           text,
    expirationDate      date,
    site_cc             jsonb,
    route_cc            jsonb,
    doseQuantity        jsonb,
    performer           jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    isSubpotent         boolean,
    subpotentReason_cc  jsonb DEFAULT '[]',
    education           jsonb DEFAULT '[]',
    programEligibility_cc jsonb DEFAULT '[]',
    fundingSource_cc    jsonb,

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- MEDICATION STATEMENT  (FHIR Resource: MedicationStatement)
-- ============================================================
CREATE TABLE medication_statement (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'MedicationStatement',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    basedOn             jsonb DEFAULT '[]',
    partOf              jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('active','completed','entered-in-error','intended','stopped','on-hold','unknown','not-taken')),
    statusReason        jsonb DEFAULT '[]',
    category_cc         jsonb,
    medication_cc       jsonb,
    medication_reference jsonb,
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    context_id          uuid REFERENCES encounter(id),
    context_display     text,
    effectiveDateTime   timestamptz,
    effectivePeriod     jsonb,
    dateAsserted        timestamptz,
    informationSource   jsonb,
    derivedFrom         jsonb DEFAULT '[]',
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    dosage              jsonb DEFAULT '[]',

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- MEDICATION REQUEST  (FHIR Resource: MedicationRequest)
-- ============================================================
CREATE TABLE medication_request (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'MedicationRequest',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('draft','active','on-hold','revoked','completed','entered-in-error','stopped','unknown')),
    statusReason_cc     jsonb,
    intent              text NOT NULL CHECK (intent IN ('proposal','plan','order','original-order','reflex-order','filler-order','instance-order','option')),
    category_cc         jsonb DEFAULT '[]',
    priority            text CHECK (priority IN ('routine','urgent','stat','asap')),
    doNotPerform        boolean DEFAULT false,
    reported_boolean    boolean,
    reported_reference  jsonb,
    medication_cc       jsonb,
    medication_reference jsonb,
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    supportingInformation jsonb DEFAULT '[]',
    authoredOn          timestamptz,
    requester           jsonb,
    performer           jsonb,
    performerType_cc    jsonb,
    recorder            jsonb,
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    instantiatesCanonical text[],
    instantiatesUri     text[],
    basedOn             jsonb DEFAULT '[]',
    groupIdentifier     jsonb,
    courseOfTherapyType_cc jsonb,
    insurance           jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    dosageInstruction   jsonb DEFAULT '[]',
    dispenseRequest     jsonb,
    substitution        jsonb,
    priorPrescription   jsonb,
    detectedIssue       jsonb DEFAULT '[]',
    eventHistory        jsonb DEFAULT '[]',

    -- Local
    dose_text           text,
    route               text,
    frequency           text,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- PROCEDURE  (FHIR Resource: Procedure)
-- ============================================================
CREATE TABLE procedure (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Procedure',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    instantiatesCanonical text[],
    instantiatesUri     text[],
    basedOn             jsonb DEFAULT '[]',
    partOf              jsonb,
    status              text NOT NULL CHECK (status IN ('preparation','in-progress','not-done','on-hold','stopped','completed','entered-in-error','unknown')),
    statusReason_cc     jsonb,
    category_cc         jsonb,
    code_cc             jsonb,
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    performedDateTime   timestamptz,
    performedPeriod     jsonb,
    performedString     text,
    performedAge        jsonb,
    performedRange      jsonb,
    recorder_id         uuid REFERENCES practitioner(id),
    recorder_display    text,
    asserter_id         uuid REFERENCES practitioner(id),
    asserter_display    text,
    performer           jsonb DEFAULT '[]',
    location            jsonb,
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    bodySite_cc         jsonb DEFAULT '[]',
    outcome_cc          jsonb,
    report              jsonb DEFAULT '[]',
    complication_cc     jsonb DEFAULT '[]',
    complicationDetail  jsonb DEFAULT '[]',
    followUp_cc         jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    focalDevice         jsonb DEFAULT '[]',
    usedReference       jsonb DEFAULT '[]',
    usedCode_cc         jsonb DEFAULT '[]',

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- SERVICE REQUEST  (FHIR Resource: ServiceRequest)
-- ============================================================
CREATE TABLE service_request (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'ServiceRequest',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    instantiatesCanonical text[],
    instantiatesUri     text[],
    basedOn             jsonb DEFAULT '[]',
    replaces            jsonb DEFAULT '[]',
    requisition         jsonb,
    status              text NOT NULL CHECK (status IN ('draft','active','on-hold','revoked','completed','entered-in-error','unknown')),
    intent              text NOT NULL CHECK (intent IN ('proposal','plan','directive','order','original-order','reflex-order','filler-order','instance-order','option')),
    category_cc         jsonb DEFAULT '[]',
    priority            text CHECK (priority IN ('routine','urgent','asap','stat')),
    doNotPerform        boolean DEFAULT false,
    code_cc             jsonb,
    orderDetail         jsonb DEFAULT '[]',
    quantityQuantity    jsonb,
    quantityRatio       jsonb,
    quantityRange       jsonb,
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    occurrenceDateTime  timestamptz,
    occurrencePeriod    jsonb,
    occurrenceTiming    jsonb,
    authoredOn          timestamptz,
    requester           jsonb,
    performerType_cc    jsonb,
    performer           jsonb,
    locationCode_cc     jsonb DEFAULT '[]',
    locationReference   jsonb DEFAULT '[]',
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    insurance           jsonb DEFAULT '[]',
    supportingInfo      jsonb DEFAULT '[]',
    specimen            jsonb DEFAULT '[]',
    bodySite_cc         jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    patientInstruction  text,
    relevantHistory     jsonb DEFAULT '[]',

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- DIAGNOSTIC REPORT  (FHIR Resource: DiagnosticReport)
-- ============================================================
CREATE TABLE diagnostic_report (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'DiagnosticReport',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    basedOn             jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('registered','partial','preliminary','final','amended','corrected','appended','cancelled','entered-in-error','unknown')),
    category_cc         jsonb DEFAULT '[]',
    code_cc             jsonb NOT NULL,
    subject_id          uuid REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    effectiveDateTime   timestamptz,
    effectivePeriod     jsonb,
    issued              timestamptz,
    performer           jsonb DEFAULT '[]',
    resultsInterpreter  jsonb DEFAULT '[]',
    specimen            jsonb DEFAULT '[]',
    result              jsonb DEFAULT '[]',   -- Reference(Observation)
    imagingStudy        jsonb DEFAULT '[]',
    media               jsonb DEFAULT '[]',
    conclusion          text,
    conclusionCode_cc   jsonb DEFAULT '[]',
    presentedForm       jsonb DEFAULT '[]',

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- DOCUMENT REFERENCE  (FHIR Resource: DocumentReference)
-- Replaces: past_investigation_reference
-- ============================================================
CREATE TABLE document_reference (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'DocumentReference',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    basedOn             jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('current','superseded','entered-in-error')),
    docStatus           text CHECK (docStatus IN ('preliminary','final','amended','entered-in-error')),
    type_cc             jsonb,
    category_cc         jsonb DEFAULT '[]',
    subject_id          uuid REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    date                timestamptz,
    author              jsonb DEFAULT '[]',
    authenticator       jsonb,
    custodian           jsonb,
    relatesTo           jsonb DEFAULT '[]',
    description         text,
    securityLabel_cc    jsonb DEFAULT '[]',
    content             jsonb DEFAULT '[]',
    context             jsonb,

    -- Local
    external_ref        text,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- IMAGING STUDY  (FHIR Resource: ImagingStudy)
-- ============================================================
CREATE TABLE imaging_study (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'ImagingStudy',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    status              text NOT NULL CHECK (status IN ('registered','available','cancelled','entered-in-error','unknown')),
    modality_cc         jsonb DEFAULT '[]',
    subject_id          uuid NOT NULL REFERENCES patient(id),
    subject_display     text,
    encounter_id        uuid REFERENCES encounter(id),
    encounter_display   text,
    started             timestamptz,
    basedOn             jsonb DEFAULT '[]',
    referrer            jsonb,
    interpreter         jsonb DEFAULT '[]',
    endpoint            jsonb DEFAULT '[]',
    numberOfSeries      integer,
    numberOfInstances   integer,
    procedureReference  jsonb,
    procedureCode_cc    jsonb DEFAULT '[]',
    location            jsonb,
    reasonCode_cc       jsonb DEFAULT '[]',
    reasonReference     jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',
    description         text,
    series              jsonb DEFAULT '[]',

    -- Local
    image_ref           text,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- SPECIMEN  (FHIR Resource: Specimen)
-- ============================================================
CREATE TABLE specimen (
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type       text NOT NULL DEFAULT 'Specimen',
    meta_version_id     text,
    meta_last_updated   timestamptz,
    meta_profile        text[],
    meta_security       jsonb DEFAULT '[]',
    meta_tag            jsonb DEFAULT '[]',
    text_status         text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div            text,
    extensions          jsonb DEFAULT '[]',
    language            text,

    identifier          jsonb DEFAULT '[]',
    accessionIdentifier jsonb,
    status              text CHECK (status IN ('available','unavailable','unsatisfactory','entered-in-error')),
    type_cc             jsonb,
    subject_id          uuid REFERENCES patient(id),
    subject_display     text,
    receivedTime        timestamptz,
    parent              jsonb DEFAULT '[]',
    request             jsonb DEFAULT '[]',
    collection          jsonb,
    processing          jsonb DEFAULT '[]',
    container           jsonb DEFAULT '[]',
    condition_cc        jsonb DEFAULT '[]',
    note                jsonb DEFAULT '[]',

    created_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- CONSENT  (FHIR Resource: Consent)
-- ============================================================
CREATE TABLE consent (
    id                       uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type            text NOT NULL DEFAULT 'Consent',
    meta_version_id          text,
    meta_last_updated        timestamptz,
    meta_profile             text[],
    meta_security            jsonb DEFAULT '[]',
    meta_tag                 jsonb DEFAULT '[]',
    text_status              text CHECK (text_status IN ('generated','extensions','additional','empty')),
    text_div                 text,
    extensions               jsonb DEFAULT '[]',
    language                 text,

    identifier               jsonb DEFAULT '[]',
    status                   text NOT NULL CHECK (status IN ('draft','proposed','active','rejected','inactive','entered-in-error')),
    scope_cc                 jsonb NOT NULL,
    category_cc              jsonb DEFAULT '[]',
    patient_id               uuid NOT NULL REFERENCES patient(id),
    patient_display          text,
    dateTime                 timestamptz,
    performer                jsonb DEFAULT '[]',
    organization             jsonb DEFAULT '[]',
    source_attachment        jsonb,
    source_reference         jsonb,
    policy                   jsonb DEFAULT '[]',
    policyRule_cc            jsonb,
    verification             jsonb DEFAULT '[]',
    provision                jsonb,
    exception                jsonb DEFAULT '[]',

    -- Local admission-specific extensions
    encounter_id             uuid REFERENCES encounter(id),
    given_by_contact_id      uuid REFERENCES patient_contact(id),
    given_by_practitioner_id uuid REFERENCES practitioner(id),
    patient_self_consent     boolean DEFAULT false,
    is_proxy_consent         boolean DEFAULT false,
    is_emergency_override    boolean DEFAULT false,
    emergency_override_reason text,
    provision_text           text,
    provision_period_start   timestamptz,
    provision_period_end     timestamptz,

    created_at               timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================
-- Patient / Person
CREATE INDEX idx_patient_name_patient       ON patient_name(patient_id);
CREATE INDEX idx_patient_address_patient    ON patient_address(patient_id);
CREATE INDEX idx_patient_identifier_patient ON patient_identifier(patient_id);
CREATE INDEX idx_patient_telecom_patient    ON patient_telecom(patient_id);
CREATE INDEX idx_patient_contact_patient    ON patient_contact(patient_id);
CREATE INDEX idx_patient_contact_guardian   ON patient_contact(patient_id, is_legal_guardian) WHERE is_legal_guardian = true;
CREATE INDEX idx_patient_contact_emergency  ON patient_contact(patient_id, is_emergency_contact) WHERE is_emergency_contact = true;
CREATE INDEX idx_patient_link_source        ON patient_link(patient_id);
CREATE INDEX idx_patient_link_target        ON patient_link(other_patient_id);
CREATE INDEX idx_patient_unidentified       ON patient(is_unidentified) WHERE is_unidentified = true;

-- Encounter
CREATE INDEX idx_encounter_patient          ON encounter(subject_id);
CREATE INDEX idx_encounter_status           ON encounter(status);
CREATE INDEX idx_encounter_period           ON encounter(period_start, period_end);
CREATE INDEX idx_encounter_participant      ON encounter_participant(encounter_id);
CREATE INDEX idx_encounter_status_history   ON encounter_status_history(encounter_id, period_start);

-- Conditions / Observations / ClinicalImpression
CREATE INDEX idx_condition_patient          ON condition(subject_id);
CREATE INDEX idx_condition_encounter        ON condition(encounter_id);
CREATE INDEX idx_condition_code             ON condition((code_cc->>'code'));
CREATE INDEX idx_observation_patient        ON observation(subject_id);
CREATE INDEX idx_observation_encounter      ON observation(encounter_id);
CREATE INDEX idx_observation_code           ON observation((code_cc->>'code'));
CREATE INDEX idx_observation_category       ON observation((category_cc->0->>'code'));
CREATE INDEX idx_clinical_impression_patient ON clinical_impression(subject_id);
CREATE INDEX idx_clinical_impression_encounter ON clinical_impression(encounter_id);

-- Medications / Procedures / Requests
CREATE INDEX idx_medication_stmt_patient    ON medication_statement(subject_id);
CREATE INDEX idx_medication_req_patient     ON medication_request(subject_id);
CREATE INDEX idx_procedure_patient          ON procedure(subject_id);
CREATE INDEX idx_service_request_patient    ON service_request(subject_id);
CREATE INDEX idx_diagnostic_report_patient  ON diagnostic_report(subject_id);
CREATE INDEX idx_document_reference_patient ON document_reference(subject_id);
CREATE INDEX idx_imaging_study_patient      ON imaging_study(subject_id);
CREATE INDEX idx_consent_patient            ON consent(patient_id);
CREATE INDEX idx_consent_encounter          ON consent(encounter_id);
CREATE INDEX idx_family_history_patient     ON family_member_history(patient_id);
CREATE INDEX idx_immunization_patient       ON immunization(patient_id);

-- GIN indexes for jsonb querying
CREATE INDEX idx_encounter_reason_gin       ON encounter USING gin(reasonCode_cc);
CREATE INDEX idx_condition_category_gin     ON condition USING gin(category_cc);
CREATE INDEX idx_observation_code_gin       ON observation USING gin(code_cc);
CREATE INDEX idx_observation_component_gin  ON observation USING gin(component);
