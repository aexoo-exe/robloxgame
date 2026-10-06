-- Traits: breakpoints and effects, as data for the Traits module. Membership comes from each
-- character's `origin` and `classes` in UnitConfig.
--
-- Empty for now: the previous traits referred to the old roster, and the new origins and classes
-- (docs/design/revamp-structure.md) are built in a later stage. With no entries, no trait counts,
-- no bonuses apply and the trait panel stays hidden.
--
-- Each entry, when added, looks like:
--   Name = {
--     kind = "origin" or "class",
--     breakpoints = { { count = 2, effects = { ... } }, ... }, -- ascending; the highest reached applies
--   }
-- Effects use the ability vocabulary and apply at combat start for the whole fight:
--   BUFF    target, stat (AD, AP, AttackSpeed, Armor, MR, MoveSpeed, MaxHealth), flat or percent
--   SHIELD  target, amount (scales with the unit's ability power), duration (seconds)
-- Targets: MEMBERS (units with the trait) or ALL_ALLIES (every unit on that player's board).

return table.freeze({})
