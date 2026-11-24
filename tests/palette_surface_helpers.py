"""Contrast helpers for independently painted capsules."""

def luminance(color):
    channels = [int(color.lstrip('#')[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return sum(weight * (c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4)
               for weight, c in zip((.2126, .7152, .0722), channels))


def contrast(foreground, background):
    values = sorted((luminance(foreground), luminance(background)))
    return (values[1] + .05) / (values[0] + .05)


def composite(foreground, background, alpha):
    return '#' + ''.join(f'{round(int(foreground[i:i + 2], 16) * alpha + int(background[i:i + 2], 16) * (1 - alpha)):02x}'
                         for i in (1, 3, 5))


def bar_contrast_samples(palette, config):
    """Measure visible text against its capsule, including group overrides."""
    bar = config['bar']['default']
    groups = {group['id']: group for group in bar.get('capsule_group', [])}
    samples = []
    def token(role):
        return palette['m' + ''.join(part.title() for part in role.split('_'))]
    for location in ('start', 'center', 'end'):
        for item in bar.get(location, []):
            group = groups[item[6:]] if item.startswith('group:') else None
            for name in group['members'] if group else [item]:
                widget = config.get('widget', {}).get(name, {})
                if widget.get('type') == 'spacer' or name == 'tray':
                    continue
                fill = (group.get('fill', bar.get('capsule_fill', 'surface_variant')) if group
                        else widget.get('capsule_fill', bar.get('capsule_fill', 'surface_variant')))
                alpha = (group.get('opacity', bar.get('capsule_opacity', 1)) if group
                         else widget.get('capsule_opacity', bar.get('capsule_opacity', 1)))
                foreground = (group.get('foreground') if group else None) or widget.get('capsule_foreground') or bar.get('capsule_foreground', 'on_surface')
                roles = {widget.get('color', foreground)}
                if 'icon_color' in widget:
                    roles.add(widget['icon_color'])
                if name == 'workspaces' and widget.get('style') == 'minimal':
                    roles.update(widget.get(key, 'on_surface_variant') for key in ('empty_color', 'occupied_color'))
                for backdrop in ('#000000', '#ffffff'):
                    background = composite(palette['mSurface'], backdrop, bar.get('background_opacity', 1))
                    if group or widget.get('capsule', bar.get('capsule', False)):
                        background = composite(token(fill), background, alpha)
                    for role in sorted(roles):
                        samples.append((name, role, token(role), background))
                    if name == 'workspaces' and widget.get('style', 'regular') != 'minimal':
                        # Regular workspace colors are PILL FILLS, not text colors.
                        # Accent fills use on_<role>; other fills use on_surface;
                        # empty pills multiply their fill alpha by 0.55.
                        defaults = {'focused_color': 'primary', 'occupied_color': 'secondary',
                                    'empty_color': 'surface_variant', 'urgent_color': 'error'}
                        for state, default in defaults.items():
                            fill_role = widget.get(state, default)
                            text_role = 'on_' + fill_role if fill_role in ('primary', 'secondary', 'tertiary', 'error') else 'on_surface'
                            pill = composite(token(fill_role), background, .55 if state == 'empty_color' else 1)
                            samples.append((name + '.' + state, text_role, token(text_role), pill))
    return samples
