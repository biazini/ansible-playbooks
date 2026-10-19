# Security Policy

## Scope

This repository contains automation content (playbooks, roles, inventories), its configuration and its documentation. Security reports are welcome for anything here that could weaken a host managed with it, for example:

- a task, template or variable that exposes a service, credential or key;
- a firewall, SSH, sudo, PAM or permission setting that is weaker than the documentation states;
- a hardening control that can lock the automation out or silently fail open;
- guidance that contradicts current CIS Benchmark or upstream security recommendations.

## Supported versions

| Content release | Ascender | ansible-core (EE) | Managed hosts | Supported |
|---|---|---|---|---|
| Current `main` | 25.6.2 | 2.16 | Ubuntu 26.04 / 24.04 LTS | ✅ |

## Reporting a vulnerability

Please **do not** disclose security problems publicly. This repository is private, so GitHub's private vulnerability reporting is not available. Report directly to the maintainer, [@biazini](https://github.com/biazini), with:

1. the affected file, role or playbook;
2. the risk and how it can be triggered;
3. a suggested correction, if you have one.

Reports are reviewed on a best-effort basis. Confirmed problems are corrected here and rolled out with the *Check (dry run)* and *Apply* job templates.

## Never commit secrets

Passwords, tokens and private keys belong in Ascender credentials. If one is ever committed or exposed, **rotate it first** (see README, 7.2 Credential rotation), then remove it from the history.

## Vulnerabilities in upstream components

Report vulnerabilities in Ascender, Ansible, collections or the operating system to their maintainers:

- Ascender: <https://github.com/ctrliq/ascender/blob/main/SECURITY.md>
- Ansible: <https://github.com/ansible/ansible/security/policy>
- Ubuntu: <https://ubuntu.com/security/disclosure-policy>
