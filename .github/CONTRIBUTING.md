# Contributing

This repository is a **private, personal automation repository**: issues are disabled and outside contributions are not accepted. The content is maintained by its owner and runs against real hosts through Ascender, so every change goes through the owner's review and the checks below.

## Rules for every change

- **Validate before pushing**: `ansible-playbook --syntax-check playbooks/*.yml` and `ansible-lint` (profile `production`) must pass.
- **Dry run before apply**: run the *Check (dry run)* job template before *Apply* for any change to a role.
- **Document with the code**: a new or changed variable is commented in the role's `defaults/main.yml`; behaviour changes are explained in the role's `README.md`; architecture changes update the `.drawio` source and its PNG export.
- **No secrets in Git**: passwords, tokens and private keys live in Ascender credentials only.
- **Commits by the owner's account only**: no co-author or tool attribution lines.

## Reporting problems

- **Security problems in this content** — privately, as described in the [security policy](SECURITY.md).
- **Problems with Ascender itself** — to its maintainers:
  - Ascender: <https://github.com/ctrliq/ascender/issues>
  - Community forum: <https://forum.ascender-automation.org>

## Conduct

Every interaction related to this project is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).
