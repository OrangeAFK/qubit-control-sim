# Fixed-point design notes

Running ledger of numeric-format decisions. Add one entry per HDL module **before**
writing its RTL (see AGENTS.md). Format:

## <module name>
Format: Q<int_bits>.<frac_bits>, signed/unsigned
Range: <min> to <max>
Rationale: <why this width>
Verified against: <golden reference / tolerance>

---
(entries go below, most recent last)
