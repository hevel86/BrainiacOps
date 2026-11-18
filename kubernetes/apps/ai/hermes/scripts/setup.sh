#!/bin/bash
set -euo pipefail

HERMES_DATA="/opt/data"
export HOME="$HERMES_DATA"
BIN_DIR="$HERMES_DATA/.local/bin"
REPOS_DIR="$HERMES_DATA/repos"
BRAINIACOPS_DIR="$REPOS_DIR/BrainiacOps"

echo "🌿 Hermes Cluster & GitOps Setup Starting..."

mkdir -p "$BIN_DIR" "$REPOS_DIR"

# 1. Install non-interactive Git HTTPS credential helper
install -m 0700 /tmp/scripts/git-askpass.sh "$BIN_DIR/git-askpass"
export GIT_ASKPASS="$BIN_DIR/git-askpass"
export GIT_TERMINAL_PROMPT=0

git config --global credential.helper ""
git config --global credential.useHttpPath true
git config --global user.name "Hermes Agent"
git config --global user.email "hermes@torquasmvo.internal"
git config --global --add safe.directory "$BRAINIACOPS_DIR"

# 2. Install & SHA-256 verify SRE / GitOps CLI tools
install_binary() {
    local name="$1"
    local version="$2"
    local url="$3"
    local expected_sha256="$4"
    local archive_type="$5" # "raw" or "targz"
    local tar_member="${6:-$name}"

    local marker="$BIN_DIR/.version-${name}-${version}"
    if [ -x "$BIN_DIR/$name" ] && [ -f "$marker" ]; then
        return 0
    fi

    echo "📦 Installing $name ($version)..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    local download_file="$tmpdir/download"

    curl -fsSL -o "$download_file" "$url"
    echo "${expected_sha256}  ${download_file}" | sha256sum -c - >/dev/null

    if [ "$archive_type" = "raw" ]; then
        install -m 0755 "$download_file" "$BIN_DIR/$name"
    else
        tar -xzf "$download_file" -C "$tmpdir"
        install -m 0755 "$tmpdir/$tar_member" "$BIN_DIR/$name"
    fi

    rm -rf "$tmpdir"
    rm -f "$BIN_DIR/.version-${name}-"*
    touch "$marker"
}

install_binary "kubectl" "v1.37.2" \
    "https://dl.k8s.io/release/v1.37.2/bin/linux/amd64/kubectl" \
    "c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4" \
    "raw"

install_binary "talosctl" "v1.14.6" \
    "https://github.com/siderolabs/talos/releases/download/v1.14.6/talosctl-linux-amd64" \
    "11acde7f7578ffe9cbe6fb8349b34595065f597de0842615982e350b365de987" \
    "raw"

install_binary "gh" "v2.104.0" \
    "https://github.com/cli/cli/releases/download/v2.104.0/gh_2.104.0_linux_amd64.tar.gz" \
    "98cb101ad87dbbd3f6b2f2bfcbd43197ccd07643140121d8a9cfaa91eadbc24e" \
    "targz" "gh_2.104.0_linux_amd64/bin/gh"

if [ -x "$BIN_DIR/gh" ] && [ ! -x "$BIN_DIR/gh.real" ]; then
    mv "$BIN_DIR/gh" "$BIN_DIR/gh.real"
elif [ -x "$BIN_DIR/gh.real" ] && ! grep -q "BRAINIAC_GITHUB_TOKEN" "$BIN_DIR/gh" 2>/dev/null; then
    mv "$BIN_DIR/gh" "$BIN_DIR/gh.real"
fi
cat > "$BIN_DIR/gh" <<'EOF'
#!/bin/sh
export GH_TOKEN="${GH_TOKEN:-${BRAINIAC_GITHUB_TOKEN:-}}"
exec /opt/data/.local/bin/gh.real "$@"
EOF
chmod 0755 "$BIN_DIR/gh"

install_binary "kustomize" "v5.8.0" \
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.0/kustomize_v5.8.0_linux_amd64.tar.gz" \
    "4dfa8307358dd9284aa4d2b1d5596766a65b93433e8fa3f9f74498941f01c5ef" \
    "targz" "kustomize"

install_binary "kubeconform" "v0.8.0" \
    "https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz" \
    "9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883" \
    "targz" "kubeconform"

install_binary "helm" "v4.3.2" \
    "https://get.helm.sh/helm-v4.3.2-linux-amd64.tar.gz" \
    "d1c0278d46beab79582d7e50f5b3dc206944ba8e577cde618513fd07daa53983" \
    "targz" "linux-amd64/helm"

install_binary "jq" "1.7.1" \
    "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" \
    "5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5" \
    "raw"

install_binary "yq" "v4.45.1" \
    "https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64" \
    "654d2943ca1d3be2024089eb4f270f4070f491a0610481d128509b2834870049" \
    "raw"

install_binary "stern" "1.35.0" \
    "https://github.com/stern/stern/releases/download/v1.35.0/stern_1.35.0_linux_amd64.tar.gz" \
    "03729b01a8fcfab25f6ea53389bd38bc37400ff86d90cd2dcda541f248cf843e" \
    "targz" "stern"

install_binary "tirith" "v0.5.0" \
    "https://github.com/sheeki03/tirith/releases/download/v0.5.0/tirith-x86_64-unknown-linux-gnu.tar.gz" \
    "e2a87b1fbb967e8d37bc9c3c19bcd97f7979c9253e2f600d9293fce4d86d07ce" \
    "targz" "tirith"

# Keep /opt/data/bin symlinked or populated for any tool expecting /opt/data/bin/tirith
mkdir -p "$HERMES_DATA/bin"
ln -sf "$BIN_DIR/tirith" "$HERMES_DATA/bin/tirith"
ln -sf "$BIN_DIR/git-askpass" "$HERMES_DATA/bin/git-askpass"

# 3. Non-destructively ensure terminal.env_passthrough in /opt/data/config.yaml
if [ -f "$HERMES_DATA/config.yaml" ]; then
    echo "🔧 Ensuring terminal.env_passthrough in config.yaml..."
    "$BIN_DIR/yq" -i '
      .terminal.env_passthrough = (
        ((.terminal.env_passthrough // []) - ["GH_TOKEN", "GITHUB_TOKEN"] + [
          "BRAINIAC_GITHUB_TOKEN",
          "GITHUB_USERNAME",
          "GIT_ASKPASS",
          "GIT_TERMINAL_PROMPT",
          "TALOSCONFIG"
        ]) | unique
      )
    ' "$HERMES_DATA/config.yaml"
fi

# 4. Persist shell environment for interactive / subshell sessions
cat > "$HERMES_DATA/hermes.env" <<EOF
export HOME="$HERMES_DATA"
export PATH="$BIN_DIR:\$PATH"
export GITHUB_USERNAME="${GITHUB_USERNAME:-hevel86}"
export GIT_ASKPASS="$BIN_DIR/git-askpass"
export GIT_TERMINAL_PROMPT=0
export TALOSCONFIG="/var/run/secrets/hermes-talos-reader/talosconfig"
[ -n "\${BRAINIAC_GITHUB_TOKEN:-}" ] && export GH_TOKEN="\${BRAINIAC_GITHUB_TOKEN}" && export GITHUB_TOKEN="\${BRAINIAC_GITHUB_TOKEN}"
EOF

cat > "$HERMES_DATA/.bashrc" <<EOF
# Hermes Environment
[ -f "$HERMES_DATA/hermes.env" ] && . "$HERMES_DATA/hermes.env"
EOF

# 5. Pre-clone or fetch BrainiacOps repository for fast diagnosis and PRs
if [ ! -d "$BRAINIACOPS_DIR/.git" ]; then
    echo "📥 Cloning hevel86/BrainiacOps into $BRAINIACOPS_DIR..."
    git clone https://github.com/hevel86/BrainiacOps.git "$BRAINIACOPS_DIR" || echo "⚠️ Initial clone skipped (will retry when GH_TOKEN is active)"
else
    echo "🔄 Fetching latest origin in $BRAINIACOPS_DIR..."
    git -C "$BRAINIACOPS_DIR" fetch --prune origin || true
fi

echo "✅ Hermes Cluster & GitOps Setup Complete!"
