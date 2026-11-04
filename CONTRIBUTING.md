# Contributing

Thanks for helping make SwitchBench useful to ordinary Mac users. Small fixes, clear explanations, accessible workflows and reproducible bug reports are welcome.

## Before you start

Search existing issues. For a substantial new tool or behavior change, open a feature request explaining the real task and why the current tools do not solve it. Keep the seven tools equally discoverable; avoid a redundant dashboard or technical setup wizard.

Do not submit games, firmware, production/title keys, personal certificates, copied commercial content or download links for them. Use synthetic fixtures. See SECURITY.md for vulnerabilities and SUPPORT.md for safe troubleshooting.

## Development

Use an Apple Silicon Mac with macOS 13+ and Apple's Command Line Tools. Clone the repository, then run `bash build.sh` and `bash test.sh`. See docs/DEVELOPMENT.md for the test structure. Required checks must pass. Test the changed workflow with keyboard access, narrow windows and light/dark appearance where relevant. Do not describe agent-operated testing as independent human UAT.

Keep changes focused. Explain the problem, resulting behavior, validation and any remaining limits in the PR. Preserve originals, refuse silent output replacement, bound untrusted data, keep logs free of key values and preserve all third-party notices. Add meaningful regression coverage for behavioral changes, not tests that merely repeat implementation details.

## AI assistance and licensing

Disclose material AI assistance, name the tool, and describe what you reviewed and tested. AI-generated contributions receive the same scrutiny as other changes. Do not submit generated code you cannot explain or code whose provenance/license you cannot establish.

By contributing, you agree that your original contribution may be distributed under the project's GPL-2.0-only license. Third-party code must retain its own compatible license and attribution. You retain your rights; no CLA or assignment is required. Follow CODE_OF_CONDUCT.md.
