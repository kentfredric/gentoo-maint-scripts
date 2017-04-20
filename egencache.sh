read -r -d '' config <<'EOF'
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /usr/local/gentoo
sync-type = git
sync-url = git+ssh://git@git.gentoo.org/repo/gentoo.git
EOF

egencache --repositories-configuration="$config" --repo gentoo -j 10 --update
