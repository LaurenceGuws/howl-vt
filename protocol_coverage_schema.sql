CREATE TABLE protocols (
    id TEXT PRIMARY KEY,
    family TEXT NOT NULL,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    mnemonic TEXT NOT NULL,
    sequence TEXT NOT NULL,
    details TEXT NOT NULL,
    implemented INTEGER NOT NULL CHECK (implemented IN (0, 1)),
    unit_tested INTEGER NOT NULL CHECK (unit_tested IN (0, 1)),
    host_tested INTEGER NOT NULL CHECK (host_tested IN (0, 1)),
    unit_test_filters TEXT NOT NULL DEFAULT '',
    priority TEXT NOT NULL,
    notes TEXT NOT NULL
);

CREATE INDEX protocols_family_kind_idx ON protocols (family, kind);
CREATE INDEX protocols_status_idx ON protocols (implemented, unit_tested, host_tested);
CREATE INDEX protocols_mnemonic_idx ON protocols (mnemonic);

CREATE VIEW protocol_summary AS
SELECT
    family,
    kind,
    COUNT(*) AS entries,
    SUM(implemented) AS implemented,
    SUM(unit_tested) AS unit_tested,
    SUM(host_tested) AS host_tested
FROM protocols
GROUP BY family, kind
ORDER BY family, kind;

CREATE VIEW protocol_gaps AS
SELECT
    id,
    family,
    kind,
    name,
    mnemonic,
    sequence,
    implemented,
    unit_tested,
    host_tested,
    unit_test_filters,
    priority,
    notes
FROM protocols
WHERE implemented = 0 OR unit_tested = 0 OR host_tested = 0
ORDER BY
    CASE priority
        WHEN 'baseline' THEN 0
        WHEN 'common-app' THEN 1
        WHEN 'modern' THEN 2
        WHEN 'high' THEN 3
        WHEN 'medium' THEN 4
        WHEN 'low' THEN 5
        WHEN 'unclassified' THEN 6
        ELSE 7
    END,
    family,
    name;
