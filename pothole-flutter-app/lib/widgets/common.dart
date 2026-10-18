import 'package:flutter/material.dart';

import '../models/pothole.dart';
import '../theme.dart';

/// The standard white surface for grouped content.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: color ?? c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: borderColor ?? c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Square icon button used in screen headers.
class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.icon, required this.tooltip, this.onTap, this.showDot = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// A small red dot, for "something here needs attention".
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 20, color: c.text),
                if (showDot)
                  Positioned(
                    top: 8,
                    right: 9,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.high,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.card, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Title row at the top of a tab: a heading, an optional line above it, and actions.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.overline, this.actions = const []});

  final String title;
  final String? overline;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) Text(overline!, style: context.text.bodySmall),
                Text(title, style: context.text.headlineSmall),
              ],
            ),
          ),
          for (final (index, action) in actions.indexed) ...[
            if (index > 0) const SizedBox(width: 10),
            action,
          ],
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.trailing});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xl, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleMedium)),
          ?trailing,
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  action!,
                  style: TextStyle(color: context.colors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "High" / "Medium" / "Low" pill with a dot.
class SeverityBadge extends StatelessWidget {
  const SeverityBadge(this.severity, {super.key});

  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.of(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            severity.label,
            style: TextStyle(color: tone.color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

/// "Resolved" / "Unresolved" tag.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.resolved});

  final bool resolved;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: resolved ? c.lowSoft : c.surface,
        borderRadius: BorderRadius.circular(6),
        border: resolved ? null : Border.all(color: c.border),
      ),
      child: Text(
        resolved ? 'Resolved' : 'Unresolved',
        style: TextStyle(color: resolved ? c.low : c.muted, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Rounded square holding an icon, tinted by severity or with the brand colour.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.severity, this.size = 42, this.filled = false});

  final IconData icon;

  /// Null uses the brand colour.
  final Severity? severity;
  final double size;

  /// Solid brand background with a white icon.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = severity == null ? (color: c.primary, soft: c.primarySoft) : c.of(severity!);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c.primary : tone.soft,
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      child: Icon(icon, size: size * 0.48, color: filled ? Colors.white : tone.color),
    );
  }
}

/// One pothole in a list: icon, place, a line of details and something on the right.
class PotholeTile extends StatelessWidget {
  const PotholeTile({
    super.key,
    required this.pothole,
    required this.onTap,
    this.trailing,
    this.icon = Icons.warning_amber_rounded,
    this.selected = false,
    this.subtitle,
  });

  final Pothole pothole;
  final VoidCallback onTap;

  /// Defaults to the severity badge.
  final Widget? trailing;
  final IconData icon;
  final bool selected;

  /// Defaults to "PH-0012 · Area · 2 h ago".
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final details = subtitle ??
        [pothole.code, if (pothole.area != null && pothole.area != pothole.title) pothole.area!, timeAgo(pothole.createdAt)]
            .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        color: selected ? c.primarySoft : null,
        borderColor: selected ? c.primary : null,
        child: Row(
          children: [
            IconTile(icon: icon, severity: pothole.severity),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pothole.title, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(details, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing ?? SeverityBadge(pothole.severity),
          ],
        ),
      ),
    );
  }
}

/// A big number over a small label.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color ?? context.colors.text, height: 1.15),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Lays [children] out in equal-width columns with a gap between them.
class EqualRow extends StatelessWidget {
  const EqualRow({super.key, required this.children, this.gap = 10});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) SizedBox(width: gap),
            Expanded(child: child),
          ],
        ],
      ),
    );
  }
}

/// Small label over a value, two to a row.
class KeyValueGrid extends StatelessWidget {
  const KeyValueGrid({super.key, required this.entries});

  final List<(String label, Widget value)> entries;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cell(context, entries[i])),
          const SizedBox(width: 12),
          Expanded(child: i + 1 < entries.length ? _cell(context, entries[i + 1]) : const SizedBox()),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _cell(BuildContext context, (String, Widget) entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.$1.toUpperCase(), style: context.text.labelSmall),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          child: entry.$2,
        ),
      ],
    );
  }
}

/// A row of pill buttons where one is selected.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            Material(
              color: option == selected ? c.primary : c.card,
              shape: StadiumBorder(side: BorderSide(color: option == selected ? c.primary : c.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    label(option),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: option == selected ? Colors.white : c.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Centred grey text for an empty list.
class EmptyCard extends StatelessWidget {
  const EmptyCard(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 30),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: context.colors.muted, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Red or green inline message, with an optional retry.
class MessageBanner extends StatelessWidget {
  const MessageBanner.error(this.message, {super.key, this.onRetry}) : isError = true;
  const MessageBanner.info(this.message, {super.key, this.onRetry}) : isError = false;

  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = isError ? c.high : c.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: isError ? c.highSoft : c.primarySoft,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: c.text, fontSize: 13))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')) else const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// Back button and a centred title, for screens opened on top of the tabs.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader(this.title, {super.key, this.onBack});

  final String title;

  /// Defaults to closing the screen.
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: Row(
          children: [
            HeaderButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Back',
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                title,
                style: context.text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}
