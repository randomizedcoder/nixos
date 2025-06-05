{ config, pkgs, ... }:

{
  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Enable XDG portal
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    config.common.default = "gtk";
  };

  # Hyprland window manager configuration
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    extraConfig = ''
      # Monitor configuration
      monitor=,preferred,auto,1

      # Execute-once startup commands
      exec-once = waybar
      exec-once = swaybg -i ~/.config/hypr/wallpaper.jpg
      exec-once = hypridle
      exec-once = wl-paste --type text --watch cliphist store
      exec-once = wl-paste --type image --watch cliphist store

      # Input configuration
      input {
        kb_layout = us
        kb_variant =
        kb_model =
        kb_options =
        kb_rules =

        follow_mouse = 1
        touchpad {
          natural_scroll = true
          scroll_factor = 0.3
        }
        sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
      }

      # General settings
      general {
        gaps_in = 5
        gaps_out = 10
        border_size = 2
        col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        col.inactive_border = rgba(595959aa)
        layout = dwindle
        no_cursor_warps = true
      }

      # Decoration settings
      decoration {
        rounding = 10
        blur {
          enabled = true
          size = 3
          passes = 1
        }
        drop_shadow = true
        shadow_range = 4
        shadow_render_power = 3
        col.shadow = rgba(1a1a1aee)
      }

      # Animation settings
      animations {
        enabled = true
        bezier = myBezier, 0.05, 0.9, 0.1, 1.05
        animation = windows, 1, 7, myBezier
        animation = windowsOut, 1, 7, default, popin 80%
        animation = border, 1, 10, default
        animation = borderangle, 1, 8, default
        animation = fade, 1, 7, default
        animation = workspaces, 1, 6, default
      }

      # Layout settings
      dwindle {
        pseudotile = true
        preserve_split = true
      }

      # Gesture settings
      gestures {
        workspace_swipe = true
        workspace_swipe_fingers = 3
      }

      # Keybindings
      bind = SUPER, Q, killactive,
      bind = SUPER, RETURN, exec, ${pkgs.alacritty}/bin/alacritty
      bind = SUPER, D, exec, wofi --show drun
      bind = SUPER, F, fullscreen
      bind = SUPER, H, movefocus, l
      bind = SUPER, L, movefocus, r
      bind = SUPER, K, movefocus, u
      bind = SUPER, J, movefocus, d
      bind = SUPER, left, movewindow, l
      bind = SUPER, right, movewindow, r
      bind = SUPER, up, movewindow, u
      bind = SUPER, down, movewindow, d
      bind = SUPER SHIFT, H, movewindow, l
      bind = SUPER SHIFT, L, movewindow, r
      bind = SUPER SHIFT, K, movewindow, u
      bind = SUPER SHIFT, J, movewindow, d
      bind = SUPER, 1, workspace, 1
      bind = SUPER, 2, workspace, 2
      bind = SUPER, 3, workspace, 3
      bind = SUPER, 4, workspace, 4
      bind = SUPER, 5, workspace, 5
      bind = SUPER, 6, workspace, 6
      bind = SUPER, 7, workspace, 7
      bind = SUPER, 8, workspace, 8
      bind = SUPER, 9, workspace, 9
      bind = SUPER, 0, workspace, 10
      bind = SUPER SHIFT, 1, movetoworkspace, 1
      bind = SUPER SHIFT, 2, movetoworkspace, 2
      bind = SUPER SHIFT, 3, movetoworkspace, 3
      bind = SUPER SHIFT, 4, movetoworkspace, 4
      bind = SUPER SHIFT, 5, movetoworkspace, 5
      bind = SUPER SHIFT, 6, movetoworkspace, 6
      bind = SUPER SHIFT, 7, movetoworkspace, 7
      bind = SUPER SHIFT, 8, movetoworkspace, 8
      bind = SUPER SHIFT, 9, movetoworkspace, 9
      bind = SUPER SHIFT, 0, movetoworkspace, 10
      bind = SUPER, mouse_down, workspace, e+1
      bind = SUPER, mouse_up, workspace, e-1
      bind = SUPER, period, togglespecialworkspace, magic
      bind = SUPER SHIFT, period, movetoworkspace, special:magic
      bind = SUPER, S, togglesplit,
      bind = SUPER, P, pseudo,
      bind = SUPER, V, togglefloating,
      bind = SUPER, R, exec, wofi --show run
      bind = SUPER, Print, exec, grimblast --notify copysave area
      bind = SUPER SHIFT, Print, exec, grimblast --notify copysave screen
      bind = SUPER, X, exec, wl-clipboard-manager
      bind = SUPER, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy
    '';
  };

  # Waybar configuration
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        spacing = 4;
        modules-left = [
          "hyprland/workspaces"
          "hyprland/submap"
        ];
        modules-center = [
          "hyprland/window"
        ];
        modules-right = [
          "pulseaudio"
          "network"
          "cpu"
          "memory"
          "battery"
          "clock"
        ];
        "hyprland/workspaces" = {
          format = "{name}";
          on-click = "activate";
          sort-by-number = true;
        };
        "hyprland/window" = {
          format = "{}";
          separate-outputs = true;
        };
        "pulseaudio" = {
          format = "{icon} {volume}%";
          format-muted = "🔇";
          format-icons = {
            headphone = "🎧";
            handsfree = "📱";
            headset = "🎧";
            phone = "☎️";
            portable = "📱";
            car = "🚗";
            default = ["🔈" "🔉" "🔊"];
          };
          on-click = "pavucontrol";
        };
        "network" = {
          format-wifi = "📶 {essid}";
          format-ethernet = "🌐 {ipaddr}/{cidr}";
          format-linked = "🌐 {ifname} (No IP)";
          format-disconnected = "⚠️ Disconnected";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
        };
        "cpu" = {
          format = "🖥️ {usage}%";
          tooltip-format = "{usage}% used";
        };
        "memory" = {
          format = "🧠 {percentage}%";
          tooltip-format = "{used:0.1f}GB/{total:0.1f}GB used";
        };
        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "⚡ {capacity}%";
          format-plugged = "🔌 {capacity}%";
          format-icons = ["🔋" "🔋" "🔋" "🔋" "🔋"];
        };
        "clock" = {
          format = "🕒 {:%H:%M}";
          format-alt = "🕒 {:%Y-%m-%d %H:%M}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };
      };
    };
    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        font-weight: bold;
        min-height: 0;
      }

      window#waybar {
        background: rgba(21, 18, 27, 0.8);
        color: #cdd6f4;
      }

      #workspaces button {
        padding: 0 5px;
        background: transparent;
        color: #cdd6f4;
      }

      #workspaces button:hover {
        background: rgba(0, 0, 0, 0.2);
      }

      #workspaces button.active {
        background: #7aa2f7;
        color: #1e1e2e;
      }

      #workspaces button.urgent {
        background: #f38ba8;
        color: #1e1e2e;
      }

      #battery,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #clock {
        padding: 0 10px;
        margin: 0 5px;
      }

      #battery {
        color: #a6e3a1;
      }

      #battery.warning {
        color: #f9e2af;
      }

      #battery.critical {
        color: #f38ba8;
      }

      #network {
        color: #89b4fa;
      }

      #pulseaudio {
        color: #cba6f7;
      }

      #cpu {
        color: #f5c2e7;
      }

      #memory {
        color: #fab387;
      }

      #clock {
        color: #89dceb;
      }
    '';
  };

  # Ghostty configuration
  programs.ghostty = {
    enable = true;
    settings = {
      scrollback-sidebar = true;
      scrollback-sidebar-width = 20;
      scrollback-sidebar-position = "right";
    };
  };
}