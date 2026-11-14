# Security policy

This policy covers every repository in {{ORGANIZATION}} that has no
`SECURITY.md` of its own.

## Reporting a vulnerability

**Never report a vulnerability in an issue, a discussion or a pull request.**
Anyone who can see the repository can read those.

Report it privately to {{SECURITY_CONTACT}}, with:

* the repository and, if you know it, the file or component;
* what an attacker could do, and the steps to reproduce it;
* whether you think it is being exploited now.

You'll get an acknowledgement, and updates until it is resolved.

## If you find a secret

If you find a password, key, token or connection string in a repository,
report it the same way. Its owner must revoke and replace it: deleting it from
the code is not enough, because it stays in the history and in every clone.

Push protection blocks known secret formats before they reach GitHub. If it
blocks your push, remove the secret and push again. Don't bypass it.
