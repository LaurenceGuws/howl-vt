BEGIN IMMEDIATE;

DROP VIEW IF EXISTS protocol_summary;
DROP VIEW IF EXISTS protocol_gaps;
DROP TABLE IF EXISTS protocols;

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

WITH cleaned_entries AS (
    SELECT
        id,
        family,
        TRIM(sequence) AS raw_sequence,
        TRIM(mnemonic) AS raw_mnemonic,
        TRIM(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(description, '((``', '"'),
                            '('''')', '"'
                        ),
                        '  ', ' '
                    ),
                    '  ', ' '
                ),
                ' .', '.'
            )
        ) AS clean_details,
        implemented,
        test_verified,
        host_verified,
        priority,
        TRIM(notes) AS notes
    FROM protocol_entries
),
entry_rows AS (
    SELECT
        id,
        family,
        'sequence' AS kind,
        CASE
            WHEN id = 'csi-decrqlp' THEN 'Select Locator Events (DECSLE)'
            WHEN id = 'csi-decrqlp-2' THEN 'Request Locator Position (DECRQLP)'
            WHEN id = 'csi-csi-ps-c' THEN 'Send Device Attributes (Primary DA)'
            WHEN id = 'csi-csi-ps-c-2' THEN 'Send Device Attributes (Tertiary DA)'
            WHEN id = 'csi-csi-ps-c-3' THEN 'Send Device Attributes (Secondary DA)'
            WHEN id = 'csi-xtrevwrap2' THEN 'DEC Private Mode Set (DECSET)'
            WHEN id = 'csi-xtrevwrap2-2' THEN 'DEC Private Mode Reset (DECRST)'
            WHEN id = 'osc-italic' THEN 'Set Text Parameters (OSC, BEL terminator)'
            WHEN id = 'osc-italic-2' THEN 'Set Text Parameters (OSC, ST terminator)'
            ELSE TRIM(
                CASE
                    WHEN INSTR(clean_details, '. ') > 0 THEN SUBSTR(clean_details, 1, INSTR(clean_details, '. ') - 1)
                    ELSE clean_details
                END,
                ' .'
            )
        END AS name,
        CASE
            WHEN id = 'csi-decrqlp' THEN 'DECSLE'
            WHEN id = 'csi-decrqlp-2' THEN 'DECRQLP'
            WHEN id = 'csi-csi-ps-c' THEN 'DA'
            WHEN id = 'csi-csi-ps-c-2' THEN 'DA3'
            WHEN id = 'csi-csi-ps-c-3' THEN 'DA2'
            WHEN id = 'csi-xtrevwrap2' THEN 'DECSET'
            WHEN id = 'csi-xtrevwrap2-2' THEN 'DECRST'
            WHEN id IN ('osc-italic', 'osc-italic-2') THEN ''
            ELSE raw_mnemonic
        END AS mnemonic,
        CASE
            WHEN id = 'esc-esc-2' THEN 'ESC ]'
            WHEN id = 'esc-esc-bs' THEN 'ESC \'
            WHEN id = 'esc-esc-xx' THEN 'ESC X'
            ELSE TRIM(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(raw_sequence, '*', ''),
                                            'qu', ''' '
                                        ),
                                        'Dq', '" '
                                    ),
                                    'SP@', 'SP @'
                                ),
                                '  ', ' '
                            ),
                            '  ', ' '
                        ),
                        '; ', ';'
                    ),
                    ' ;', ';'
                )
            )
        END AS sequence,
        clean_details AS details,
        implemented,
        test_verified AS unit_tested,
        host_verified AS host_tested,
        priority,
        notes
    FROM cleaned_entries
)
INSERT INTO protocols (
    id,
    family,
    kind,
    name,
    mnemonic,
    sequence,
    details,
    implemented,
    unit_tested,
    host_tested,
    unit_test_filters,
    priority,
    notes
)
SELECT
    id,
    family,
    kind,
    name,
    mnemonic,
    sequence,
    details,
    implemented,
    unit_tested,
    host_tested,
    '',
    priority,
    notes
FROM entry_rows;

INSERT INTO protocols (
    id,
    family,
    kind,
    name,
    mnemonic,
    sequence,
    details,
    implemented,
    unit_tested,
    host_tested,
    unit_test_filters,
    priority,
    notes
)
SELECT
    'mode-' || mode,
    CASE
        WHEN family = 'DEC private' THEN 'DEC Private Mode'
        ELSE family || ' Mode'
    END,
    'mode',
    name,
    CASE
        WHEN INSTR(name, ' ') > 0 THEN SUBSTR(name, 1, INSTR(name, ' ') - 1)
        ELSE name
    END,
    'set: ' || set_sequence || ' | reset: ' || reset_sequence || ' | query: ' || query_sequence,
    'Mode ' || mode || ' in ' || family || '. Set with ' || set_sequence || ', reset with ' || reset_sequence || ', and query with ' || query_sequence || '.' ||
        CASE
            WHEN save_restore_supported = 1 THEN ' Save/restore is supported.'
            ELSE ''
        END,
    implemented,
    test_verified,
    host_verified,
    '',
    priority,
    TRIM(notes)
FROM protocol_modes;

INSERT INTO protocols (
    id,
    family,
    kind,
    name,
    mnemonic,
    sequence,
    details,
    implemented,
    unit_tested,
    host_tested,
    unit_test_filters,
    priority,
    notes
)
SELECT
    id,
    CASE family
        WHEN 'clipboard' THEN 'Clipboard'
        WHEN 'color' THEN 'Color'
        WHEN 'colors' THEN 'Color'
        WHEN 'graphics' THEN 'Kitty Graphics'
        WHEN 'keyboard' THEN 'Kitty Keyboard'
        WHEN 'notification' THEN 'Kitty Notification'
        WHEN 'pointer' THEN 'Kitty Pointer'
        WHEN 'shell' THEN 'Kitty Shell'
        WHEN 'sgr' THEN 'SGR'
        ELSE 'Kitty'
    END,
    'feature',
    CASE
        WHEN id = 'kitty-clipboard-osc52' THEN 'OSC 52 clipboard compatibility'
        ELSE name
    END,
    CASE
        WHEN id = 'kitty-clipboard-osc52' THEN 'OSC 52'
        WHEN id = 'kitty-color-control' THEN 'OSC 21'
        WHEN id = 'kitty-color-stack' THEN 'OSC 30001/30101'
        WHEN id = 'kitty-desktop-notifications' THEN 'OSC 99'
        WHEN id = 'kitty-keyboard-negotiate' THEN 'CSI u'
        WHEN id = 'kitty-keyboard-reporting' THEN 'CSI u'
        WHEN id = 'kitty-pointer-shapes' THEN 'OSC 22'
        WHEN id = 'kitty-shell-integration' THEN 'OSC 133'
        WHEN id LIKE 'kitty-graphics-%' THEN 'APC _G'
        WHEN id IN ('kitty-underline-color', 'kitty-underline-style') THEN 'SGR'
        ELSE ''
    END,
    CASE
        WHEN id = 'kitty-color-stack' THEN 'OSC 30001 / OSC 30101'
        ELSE sequence
    END,
    CASE
        WHEN id = 'kitty-clipboard-osc52' THEN 'Focused DX row for OSC 52 clipboard behavior, separate from the broader OSC text-parameter umbrella entry.'
        ELSE name || '. Sequence: ' || CASE WHEN id = 'kitty-color-stack' THEN 'OSC 30001 / OSC 30101' ELSE sequence END || '.'
    END,
    implemented,
    test_verified,
    host_verified,
    '',
    priority,
    CASE
        WHEN id = 'kitty-color-stack' THEN 'OSC 30001/30101 snapshot and restore VT-core terminal color state, including dynamic colors and the ANSI palette. Render/host consumption remains pending.'
        ELSE TRIM(notes)
    END
FROM kitty_protocols
WHERE id <> 'kitty-graphics-apc';

WITH seeds(id, filters) AS (
    VALUES
        ('csi-cbt', 'screen: horizontal_tab_back moves to previous default tab stop' || char(10) || 'replay: CSI Z moves cursor to previous default tab stop'),
        ('csi-cht', 'screen: HTS sets custom tab stop and TBC clears it' || char(10) || 'replay: CSI I advances cursor by default tab stops'),
        ('csi-csi-ps-c', 'extended report queries append host output' || char(10) || 'semantic: DA maps to primary device attributes'),
        ('csi-csi-ps-c-2', 'extended report queries append host output' || char(10) || 'semantic: DA3 maps to tertiary device attributes'),
        ('csi-csi-ps-c-3', 'extended report queries append host output' || char(10) || 'semantic: DA2 maps to secondary device attributes'),
        ('csi-csi-ps-n', 'modifyOtherKeys set query disable and encoding'),
        ('csi-csi-r', 'ANSI mode queries and XTREPORTCOLORS append host output'),
        ('csi-deccksr', 'DECXCPR appends DEC cursor position report' || char(10) || 'DEC locator DSR replies status and type' || char(10) || 'semantic: DECXCPR maps to DEC cursor position report'),
        ('csi-decefr', 'locator button and filter events append DECLRP' || char(10) || 'semantic: locator controls map'),
        ('csi-decelr', 'locator requests reply unavailable, then current position, then disable one-shot' || char(10) || 'locator button and filter events append DECLRP' || char(10) || 'semantic: locator controls map'),
        ('csi-decreqtparm', 'extended report queries append host output'),
        ('csi-decrqde', 'extended report queries append host output'),
        ('csi-decrqlp', 'locator button and filter events append DECLRP' || char(10) || 'semantic: locator controls map'),
        ('csi-decrqlp-2', 'locator requests reply unavailable, then current position, then disable one-shot' || char(10) || 'semantic: locator controls map'),
        ('csi-decrqm', 'ANSI mode queries and XTREPORTCOLORS append host output'),
        ('csi-decrqm-2', 'DEC mode queries append DECRPM replies' || char(10) || 'semantic: DECRQM maps to dec mode query'),
        ('csi-dectabsr', 'DECCIR reports default cursor information' || char(10) || 'DECCIR reports cursor position and rendition bits' || char(10) || 'DECCIR reports protection origin and wrap flags' || char(10) || 'DECCIR reports charset designation and GL shift'),
        ('csi-xtreportsgr', 'XTREPORTSGR reports common rectangle attrs conservatively' || char(10) || 'semantic: XTREPORTSGR maps to selected graphic rendition report'),
        ('csi-tbc', 'screen: HTS sets custom tab stop and TBC clears it' || char(10) || 'screen: TBC all clears defaults until reset restores them' || char(10) || 'semantic: HTS and TBC map to tab stop controls'),
        ('csi-xtmodkeys', 'modifyOtherKeys set query disable and encoding' || char(10) || 'semantic: application keypad and modifyOtherKeys mappings'),
        ('csi-xtqmodkeys', 'modifyOtherKeys set query disable and encoding'),
        ('esc-deckpam', 'application keypad modes affect keypad encoding and DECRQM' || char(10) || 'semantic: application keypad and modifyOtherKeys mappings'),
        ('esc-deckpnm', 'application keypad modes affect keypad encoding and DECRQM'),
        ('esc-esc-h', 'screen: HTS sets custom tab stop and TBC clears it' || char(10) || 'semantic: HTS and TBC map to tab stop controls'),
        ('kitty-clipboard-osc52', 'OSC 52 produces pending clipboard request'),
        ('kitty-color-control', 'kitty OSC 21 sets queries and resets terminal colors' || char(10) || 'semantic: terminal color OSC commands preserve command and payload'),
        ('kitty-color-stack', 'kitty color stack OSC 30001 and 30101 track depth' || char(10) || 'kitty color stack restores terminal color snapshots' || char(10) || 'semantic: kitty color stack OSC codes map to commands'),
        ('kitty-desktop-notifications', 'kitty notification OSC 99 queues host-neutral request' || char(10) || 'semantic: kitty notification OSC 99 splits metadata and payload'),
        ('kitty-graphics-animation-frame-upload', 'kitty graphics animation frame upload stores frame metadata'),
        ('kitty-graphics-command-parse', 'semantic: kitty graphics APC parses control keys and payload'),
        ('kitty-graphics-delete', 'kitty graphics delete by image id removes image and placements'),
        ('kitty-graphics-delete-selectors', 'kitty graphics deletion selectors remove matching placements'),
        ('kitty-graphics-direct-upload', 'kitty graphics direct upload stores single base64 payload' || char(10) || 'kitty graphics direct upload assembles chunked base64 payload'),
        ('kitty-graphics-image-number', 'kitty graphics image numbers allocate ids and place newest image'),
        ('kitty-graphics-image-replace', 'kitty graphics upload with same image id replaces image and placements'),
        ('kitty-graphics-place', 'kitty graphics place stores metadata and replies by image id' || char(10) || 'kitty graphics place missing image replies ENOENT'),
        ('kitty-graphics-query-reply', 'kitty graphics query returns conservative unsupported reply'),
        ('kitty-keyboard-negotiate', 'kitty keyboard set query push and pop flags' || char(10) || 'kitty keyboard flags stay separate across alternate screen'),
        ('kitty-keyboard-reporting', 'kitty keyboard mode switches existing keys to CSI-u family'),
        ('kitty-pointer-shapes', 'kitty pointer shape OSC 22 maintains per-screen stack and replies to queries' || char(10) || 'semantic: kitty pointer shape OSC 22 parses action and names'),
        ('kitty-shell-integration', 'kitty shell integration OSC 133 records latest mark' || char(10) || 'semantic: kitty shell integration OSC 133 parses mark and status'),
        ('mode-1', 'application cursor mode changes arrow key encoding' || char(10) || 'semantic: DEC private application cursor enable maps true'),
        ('mode-1000', 'mouse reporting supports legacy x10 normal utf8 and urxvt encodings'),
        ('mode-1002', 'mouse reporting is gated by DECSET mouse modes and SGR protocol'),
        ('mode-1003', 'mouse reporting is gated by DECSET mouse modes and SGR protocol'),
        ('mode-1004', 'focus reports are gated by DECSET 1004' || char(10) || 'semantic: DEC private focus reporting enable maps true' || char(10) || 'XTSAVE and XTRESTORE restore supported DEC private modes'),
        ('mode-1005', 'mouse mode queries and save restore include extended protocols' || char(10) || 'mouse reporting supports legacy x10 normal utf8 and urxvt encodings' || char(10) || 'semantic: DEC private mouse tracking mode mappings'),
        ('mode-1006', 'mouse reporting is gated by DECSET mouse modes and SGR protocol'),
        ('mode-1015', 'mouse mode queries and save restore include extended protocols' || char(10) || 'mouse reporting supports legacy x10 normal utf8 and urxvt encodings' || char(10) || 'semantic: DEC private mouse tracking mode mappings'),
        ('mode-1047', 'alternate screen exit preserves primary scrollback' || char(10) || 'alternate screen switches mark active viewport fully dirty'),
        ('mode-1049', 'alternate screen 1049 restores primary cursor' || char(10) || 'alternate screen exit preserves primary scrollback' || char(10) || 'alternate screen switches mark active viewport fully dirty'),
        ('mode-2004', 'bracketed paste wrappers are gated by DECSET 2004' || char(10) || 'semantic: DEC private bracketed paste disable maps false' || char(10) || 'XTSAVE and XTRESTORE restore supported DEC private modes'),
        ('mode-25', 'semantic: DEC private cursor show maps to cursor_visible true' || char(10) || 'semantic: DEC private cursor hide maps to cursor_visible false' || char(10) || 'XTSAVE and XTRESTORE restore supported DEC private modes'),
        ('mode-47', 'alternate screen exit preserves primary scrollback' || char(10) || 'alternate screen switches mark active viewport fully dirty'),
        ('mode-66', 'application keypad modes affect keypad encoding and DECRQM' || char(10) || 'semantic: application keypad and modifyOtherKeys mappings'),
        ('mode-7', 'semantic: DEC private wrap enable maps to auto_wrap true' || char(10) || 'semantic: DEC private wrap disable maps to auto_wrap false' || char(10) || 'XTSAVE and XTRESTORE restore supported DEC private modes'),
        ('mode-9', 'mouse reporting supports legacy x10 normal utf8 and urxvt encodings' || char(10) || 'semantic: DEC private mouse tracking mode mappings')
)
UPDATE protocols
SET unit_test_filters = (SELECT filters FROM seeds WHERE seeds.id = protocols.id)
WHERE id IN (SELECT id FROM seeds);

UPDATE protocols
SET notes = 'DEC-specific DSR replies now cover DECXCPR plus locator status/type reports for Ps=55 and Ps=56.'
WHERE id = 'csi-deccksr';

UPDATE protocols
SET implemented = 1,
    unit_tested = 1,
    host_tested = 0,
    notes = 'Implemented conservative XTREPORTSGR replies using attributes common across a requested rectangle.',
    unit_test_filters = 'XTREPORTSGR reports common rectangle attrs conservatively' || char(10) || 'semantic: XTREPORTSGR maps to selected graphic rendition report'
WHERE id = 'csi-xtreportsgr';

DROP TABLE IF EXISTS kitty_protocol_test_refs;
DROP TABLE IF EXISTS protocol_test_refs;
DROP TABLE IF EXISTS protocol_mode_test_refs;
DROP TABLE IF EXISTS kitty_protocols;
DROP TABLE IF EXISTS protocol_modes;
DROP TABLE IF EXISTS protocol_entries;
DROP TABLE IF EXISTS metadata;

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

COMMIT;

VACUUM;
