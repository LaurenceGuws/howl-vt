SELECT
  unit_tested,
  mnemonic,
  family,
  name,
  notes,
  sequence,
  priority,
FROM protocols
ORDER BY
  unit_tested DESC,
  family ASC,
  kind ASC,
  name ASC;