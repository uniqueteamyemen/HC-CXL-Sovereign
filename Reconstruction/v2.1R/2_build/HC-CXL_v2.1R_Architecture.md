# HC-CXL v2.1R — System Architecture

## Reference Digest
B6C66BD929F46B8BF6B920BA6C634972E7B83CA607AD4B5A1042B4AC06A1E203

## Layered Architecture (7 Layers)
1. Immutable Core (SISB)
2. Hardware Infrastructure
3. CXL Physical Link
4. HC-CXL Protocol Logic
5. Physics-Bounded Execution
6. W_PMP Logical Ordering
7. Internal Verification Lattice (IVL)

## Notes
- Architecture updated to enforce Pre-Sterilization using digest B6C66BD929F46B8BF6B920BA6C634972E7B83CA607AD4B5A1042B4AC06A1E203.
- W_PMP is now evaluated before constraints, per v2.1R rules.
