#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
RUNTIME_DIR="/run/user/${TARGET_UID}"
DISPLAY_VAL="${DISPLAY:-:0}"
USER_BUS="unix:path=${RUNTIME_DIR}/bus"
SESSION_TYPE="$(loginctl show-session "$XDG_SESSION_ID" -p Type --value 2>/dev/null || echo "${XDG_SESSION_TYPE:-unknown}")"

msg(){ printf "\n==> %s\n" "$*"; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }

gsettings(){
  sudo -u "$TARGET_USER" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
    DISPLAY="$DISPLAY_VAL" \
    gset "$@"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0"; exit 1
fi
if [ ! -S "${RUNTIME_DIR}/bus" ]; then
  cat <<EOF
No user session bus at ${RUNTIME_DIR}/bus.
Open a terminal in ${TARGET_USER}'s *logged-in desktop* session and run:
  sudo bash $0
EOF
  exit 1
fi

msg "Updating apt cache"
apt update -y

msg "Installing base utilities"
apt install -y gnome-shell-extension-manager chrome-gnome-shell make gettext git curl gpg

msg "Installing GNOME Tweaks and Startup Applications"
apt install -y gnome-tweaks gnome-startup-applications

if ! need_cmd google-chrome; then
  msg "Installing Google Chrome (stable)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
  apt update -y
  apt install -y google-chrome-stable
fi

msg "Installing snap applications"
if ! need_cmd snap; then
  apt install -y snapd
fi

snap install gitkraken --classic
snap install spotify
snap install discord

msg "Enabling Night Light"
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3700
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true

msg "Installing gnome-screenshot and binding Shift+Super+S"
apt install -y gnome-screenshot
BPATH_SS="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$BPATH_SS']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BPATH_SS name "'Area Screenshot to Clipboard'"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BPATH_SS command "'gnome-screenshot --area --clipboard'"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BPATH_SS binding "'<Shift><Super>s'"

msg "Installing Dash to Panel"
TMPDIR="$(mktemp -d)"
git clone https://github.com/home-sweet-gnome/dash-to-panel.git "$TMPDIR/dash-to-panel"
make -C "$TMPDIR/dash-to-panel" install
rm -rf "$TMPDIR"

msg "Enabling Dash to Panel and setting panel to bottom"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DISPLAY="$DISPLAY_VAL" \
  gnome-extensions enable dash-to-panel@jderose9.github.com || true
gsettings set org.gnome.shell.extensions.dash-to-panel panel-position 'BOTTOM'

if [ "$SESSION_TYPE" = "wayland" ]; then
  msg "Wayland detected → skip 'gnome-shell --replace'. Log out/in once to see the panel."
else
  msg "Xorg detected → you can press Alt+F2, type r, Enter to restart GNOME Shell."
fi

TERMINAL_DESKTOP="org.gnome.Terminal.desktop"
[ -f /usr/share/applications/$TERMINAL_DESKTOP ] || TERMINAL_DESKTOP="org.gnome.Console.desktop"

msg "Setting favorites on the taskbar"
CURRENT_FAVS="$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DISPLAY="$DISPLAY_VAL" gsettingstings get org.gnome.shell favorite-apps)"
python3 - <<PY | sed -e "s/^/gsettings set org.gnome.shell favorite-apps '/" -e "s/$/'/" | bash
import ast, os
cur = ast.literal_eval("""$CURRENT_FAVS""")
bad = ("firefox", "snap-store", "software", "yelp", "help")
cur = [x for x in cur if all(b not in x.lower() for b in bad)]
want = [
  "org.gnome.SystemMonitor.desktop",
  "$TERMINAL_DESKTOP",
  "org.gnome.Settings.desktop",
  "google-chrome.desktop",
]wwer
for w in want:
    if w not in cur:
        cur.append(w)
print(str(cur))
PY

msg "Applying workspace & UI keybindings"
gsettings set org.gnome.desktop.wm.preferences num-workspaces 8
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>Z']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>X']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>C']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>A']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Super>Q']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-6 "['<Super>W']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-7 "['<Super>E']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-8 "['<Super>R']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Super><Shift>less']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Super><Shift>z']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Super><Shift>x']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Super><Shift>c']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Super><Shift>a']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Super><Shift>q']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-6 "['<Super><Shift>w']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-7 "['<Super><Shift>e']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-8 "['<Super><Shift>r']"
gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>Tab']"
gsettings set org.gnome.shell.keybindings toggle-application-view "[]"
gsettings set org.gnome.shell.keybindings toggle-quick-settings "[]"
gsettings set org.gnome.mutter overlay-key ''
gsettings set org.gnome.desktop.interface enable-animations false

# enable global workspaces across all monitors
gsettings set org.gnome.mutter workspaces-only-on-primary false

msg "Installing Albert from OBS repo and enabling autostart"
rm -f /etc/apt/sources.list.d/albert*.list
rm -f /etc/apt/trusted.gpg.d/albert*.gpg /etc/apt/keyrings/albert-obs.gpg
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_24.04/Release.key \
  | gpg --dearmor | tee /etc/apt/keyrings/albert-obs.gpg >/dev/null
echo 'deb [signed-by=/etc/apt/keyrings/albert-obs.gpg] https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_24.04/ /' \
  > /etc/apt/sources.list.d/albert-obs.list
apt update -y
apt install -y albert

sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/autostart"
cp /usr/share/applications/albert.desktop "/home/$TARGET_USER/.config/autostart/" || true

msg "Binding F19 to 'albert toggle'"
EXIST_KEYS="$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DISPLAY="$DISPLAY_VAL" gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings || echo "[]")"
BPATH_AL="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
python3 - <<PY | sed -e "s/^/gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings '/" -e "s/$/'/" | bash
import ast
cur = ast.literal_eval("""$EXIST_KEYS""") if """$EXIST_KEYS""".strip() else []
p = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
if p not in cur: cur.append(p)
print(str(cur))
PY
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BPATH_AL name "'Albert Toggle'"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BPATH_AL command "'albert toggle'"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$BPATH_AL binding "'F19'"

msg "Installing keyd and applying your config (Caps->F19; Ctrl+Caps = CapsLock)"
add-apt-repository -y ppa:keyd-team/ppa || true
apt update -y
apt install -y keyd
cat >/etc/keyd/default.conf <<'KEYD'
[ids]
*

[global]
chord_timeout = 120

[main]
capslock = f19

leftcontrol = layer(control)

leftcontrol+capslock  = capslock
rightcontrol+capslock = capslock
KEYD
systemctl enable --now keyd
systemctl restart keyd

msg "Installing optional xbindkeys fallback"
apt install -y xbindkeys
sudo -u "$TARGET_USER" bash -lc 'cat > ~/.xbindkeysrc <<XKC
"albert toggle"
  F19
XKC'

msg "Installing Solaar"
apt install -y solaar
sudo -u "$TARGET_USER" bash -lc 'mkdir -p ~/.config/autostart && cp /usr/share/applications/solaar.desktop ~/.config/autostart/ || true'
sudo -u "$TARGET_USER" bash -lc 'solaar config "G502 LIGHTSPEED Wireless Gaming Mouse" dpi 1600 >/dev/null 2>&1 || true'
sudo -u "$TARGET_USER" bash -lc 'solaar config "G502 LIGHTSPEED Wireless Gaming Mouse" onboard_profiles false >/dev/null 2>&1 || true'

msg "Installing UV for the user (via official script)"
sudo -u "$TARGET_USER" bash -lc 'curl -LsSf https://astral.sh/uv/install.sh | sh || true'

msg "Setting up uv run python main.py --config config.json for startup"
sudo -u "$TARGET_USER" bash -lc 'mkdir -p ~/.config/autostart'
sudo -u "$TARGET_USER" bash -lc 'cat > ~/.config/autostart/uv-python.desktop <<EOF
[Desktop Entry]
Type=Application
Name=UV Python Main
Exec=bash -c "cd ~/projects/phrase_gen_flow && uv run python main.py --config config.json"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF'

msg "Audit: grep some keybindings"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DISPLAY="$DISPLAY_VAL" \
  bash -lc "gsettings list-recursively | grep -E '<Super>Tab|switch-group|switch-applications' || true"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DISPLAY="$DISPLAY_VAL" \
  bash -lc "gsettings list-recursively | grep '<Super>s' || true"

if [[ "$SESSION_TYPE" =~ ^(x11|xorg)$ ]]; then
  msg "Xorg: setting MAX refresh per monitor via xrandr (best effort)"
  apt install -y x11-xserver-utils
  sudo -u "$TARGET_USER" DISPLAY="$DISPLAY_VAL" bash -lc '
    if command -v xrandr >/dev/null; then
      while read -r out _ status _; do
        [ "$status" = "connected" ] || continue
        best_line=$(xrandr --query \
          | awk -v o="$out" "
              /^\"?\"?\"?\"?$/ {next}
              \$0 ~ (\"^\" o \" \") {inblk=1; next}
              inblk && /^[A-Za-z0-9-]+ connected/ {inblk=0}
              inblk && /^[[:space:]]*[0-9]+x[0-9]+/ {
                mode=\$1
                for(i=2;i<=NF;i++){
                  if(index(\$i,\"+\")||index(\$i,\"*\")||\$i ~ /^[0-9.]+$/){
                    gsub(/[*+]/, \"\", \$i)
                    rate=\$i
                    printf(\"%s %s\\n\", mode, rate)
                  }
                }
              }" \
          | sort -k2,2nr -k1,1 | head -n1)
        mode=${best_line% *}; rate=${best_line##* }
        if [ -n "$mode" ] && [ -n "$rate" ]; then
          xrandr --output "$out" --mode "$mode" --rate "$rate" || true
        fi
      done < <(xrandr --query | awk "/ connected/{print \$1, \$2}")
    fi
  '
else
  msg "Wayland: enabling VRR experimental feature (if supported)"
  gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']"
fi

sudo apt install -y gammastep x11-xserver-utils desktop-file-utils

gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled false

mkdir -p ~/.config/gammastep
cat > ~/.config/gammastep/config.ini << 'EOF'
[general]
temp-day=6500
temp-night=2000
gamma=0.9
fade=1
adjustment-method=randr
location-provider=manual

[manual]
lat=60.5750
lon=26.8944
EOF

mkdir -p ~/.local/bin ~/.local/share
cat > ~/.local/bin/gammastep-start << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="$HOME/.local/share/gammastep-autostart.log"

exec 9>"$HOME/.local/share/gammastep.lock"
if ! flock -n 9; then exit 0; fi
if pgrep -x gammastep >/dev/null 2>&1; then exit 0; fi

: "${DISPLAY:=}"
if [ -z "$DISPLAY" ]; then
  for d in :0 :1 :2; do
    if XAUTHORITY="$HOME/.Xauthority" DISPLAY="$d" xrandr --listmonitors >/dev/null 2>&1; then
      export DISPLAY="$d"
      break
    fi
  done
fi

for _ in {1..20}; do
  xrandr --listmonitors >/dev/null 2>&1 && break
  sleep 0.5
done

pkill -x gammastep >/dev/null 2>&1 || true
exec gammastep -m randr -c "$HOME/.config/gammastep/config.ini" >> "$LOG" 2>&1
EOF
chmod +x ~/.local/bin/gammastep-start

mkdir -p ~/.config/autostart
cat > ~/.config/autostart/gammastep.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=gammastep
Exec=/home/mk/.local/bin/gammastep-start
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=8
EOF

desktop-file-validate ~/.config/autostart/gammastep.desktop || true

systemctl --user disable --now gammastep.service 2>/dev/null || true
rm -f ~/.config/systemd/user/gammastep.service 2>/dev/null || true
systemctl --user daemon-reload || true
grep -ril 'gammastep' ~/.config/autostart 2>/dev/null | grep -v 'gammastep.desktop' | xargs -r rm -f

pkill -x gammastep 2>/dev/null || true
nohup ~/.local/bin/gammastep-start >/dev/null 2>&1 &
sleep 1
pgrep -a gammastep || tail -n +1 ~/.local/share/gammastep-autostart.log

sudo apt install remmina remmina-plugin-rdp remmina-plugin-secret -y

sudo apt install tmux -y

tmux set -g mouse on
tmux set -g history-limit 200000
tmux set -g mode-keys vi

msg "Done. On Wayland, log out/in once so Dash to Panel fully appears."
