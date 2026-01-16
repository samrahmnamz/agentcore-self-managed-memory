# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2024

### Changed
- Restructured project to follow AWS open source best practices
- Moved Lambda function code to `functions/memory_processor/app.py`
- Moved infrastructure to `infra/cloudformation/`
- Moved operational scripts to `scripts/` directory
- Renamed `infrastructure.yaml` to `template.yaml`
- Updated Makefile to reference new paths

### Added
- LICENSE (Apache 2.0)
- CODE_OF_CONDUCT.md
- CONTRIBUTING.md
- .gitleaksignore for security
- .env.example template
- functions/memory_processor/requirements.txt

### Maintained
- `src/` directory structure (required by AgentCore CLI)
- All existing Makefile targets and workflows
- Backward compatibility with deployment scripts
