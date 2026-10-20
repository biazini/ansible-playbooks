# Contributing

Thank you for your interest in this repository.

This is a **personal automation repository, published for reference**: issues are disabled and outside contributions are not accepted. The content is maintained by its owner and runs against real hosts through Ascender, so every change goes through the owner's review and the checks below.

## What you can do

- **Use it.** Clone or fork the repository and adapt the roles and playbooks to your environment, under the terms of the [licenses](../README.md#license): MIT for code and configuration files, CC BY 4.0 for documentation and diagrams. Validate every change in a non-production environment first.
- **Report a security problem** in this content privately, as described below.

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
