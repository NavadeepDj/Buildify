import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/ai_server_provider.dart';
import 'project_detail_page.dart';

class DeploymentPage extends ConsumerStatefulWidget {
  const DeploymentPage({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<DeploymentPage> createState() => _DeploymentPageState();
}

class _DeploymentPageState extends ConsumerState<DeploymentPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _startingServer = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_DeployItem> get _filteredItems {
    if (_query.isEmpty) return _items;
    final q = _query.toLowerCase();
    return _items.where((i) => i.searchText.toLowerCase().contains(q)).toList();
  }

  void _openDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectDetailPage(projectId: widget.projectId),
      ),
    );
  }

  Future<void> _startServer() async {
    if (_startingServer) return;
    setState(() => _startingServer = true);
    try {
      await ref
          .read(embeddedBackendProvider)
          .startSession(projectId: widget.projectId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Server started')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start server: $error')));
    } finally {
      if (mounted) setState(() => _startingServer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final items = _filteredItems;

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _DeploymentColors.surface,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: _DeploymentColors.primary,
          selectionColor: _DeploymentColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Scaffold(
        backgroundColor: _DeploymentColors.surface,
        body: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: 64 + top,
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                  left: 16,
                  right: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ServiceMetaCard(
                      starting: _startingServer,
                      onStartServer: _startServer,
                    ),
                    const SizedBox(height: 16),
                    const _InactivityBanner(),
                    const SizedBox(height: 24),
                    _SearchBar(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 16),
                    _SectionHeading(count: _query.isEmpty ? 20 : items.length),
                    const SizedBox(height: 10),
                    if (items.isEmpty)
                      _NoResults(query: _query)
                    else
                      ...items.map(
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _DeployCard(item: i, onTap: _openDetails),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const _TerminalHealth(),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 64 + top,
              child: _Header(
                onBack: () => Navigator.of(context).maybePop(),
                onHome:
                    () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onHome});

  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      color: _DeploymentColors.surface,
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _PressedScale(
                onTap: onBack,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: _DeploymentColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: onHome,
                style: TextButton.styleFrom(
                  foregroundColor: _DeploymentColors.onSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'home',
                  style: _DeploymentText.headlineLg(
                    color: _DeploymentColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '/',
                style: _DeploymentText.headlineLg(
                  color: _DeploymentColors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Deployment Logs',
                  style: _DeploymentText.headlineLg(
                    color: _DeploymentColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceMetaCard extends StatelessWidget {
  const _ServiceMetaCard({required this.starting, required this.onStartServer});

  final bool starting;
  final VoidCallback onStartServer;

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DeploymentColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.public,
                size: 14,
                color: _DeploymentColors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'WEB SERVICE',
                style: _DeploymentText.labelCaps(
                  color: _DeploymentColors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _DeploymentColors.successGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE',
                style: _DeploymentText.labelCaps(
                  color: _DeploymentColors.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'PaperStudio',
                style: _DeploymentText.headlineMd(
                  color: _DeploymentColors.onSurface,
                ),
              ),
              const _MetaBadge('Docker'),
              const _MetaBadge(
                'Free',
                background: _DeploymentColors.secondaryContainer,
                foreground: _DeploymentColors.onSecondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PressedScale(
            onTap: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Upgrade your instance',
                  style: _DeploymentText.bodySm(
                    color: _DeploymentColors.primary,
                    weight: FontWeight.w700,
                  ).copyWith(decoration: TextDecoration.underline),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward,
                  size: 13,
                  color: _DeploymentColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ActionButton(
            icon: Icons.play_arrow,
            label: starting ? 'Starting...' : 'Start Server',
            busy: starting,
            onTap: onStartServer,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: _DeploymentColors.surfaceContainerLowest.withValues(
                alpha: 0.55,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _MetaLine(
                  label: 'Service ID:',
                  child: _PressedScale(
                    onTap:
                        () => _copy(
                          context,
                          'srv-d6jhtp7tskes7380obp0',
                          'Service ID copied',
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'srv-d6jhtp7tskes7380obp0',
                            style: _DeploymentText.caption(
                              color: _DeploymentColors.secondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.content_copy,
                          size: 13,
                          color: _DeploymentColors.outline,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _MetaLine(
                  label: 'Repository:',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.code,
                        size: 14,
                        color: _DeploymentColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Sujith8257/PaperStudio',
                          style: _DeploymentText.caption(
                            color: _DeploymentColors.secondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _MetaLine(
                  label: 'Ref / Commit:',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fork_right,
                        size: 13,
                        color: _DeploymentColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'main',
                        style: _DeploymentText.caption(
                          color: _DeploymentColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/',
                        style: _DeploymentText.caption(
                          color: _DeploymentColors.outline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.commit,
                        size: 13,
                        color: _DeploymentColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'b3dd324',
                        style: _DeploymentText.caption(
                          color: _DeploymentColors.secondary,
                        ).copyWith(decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _MetaLine(
                  label: 'Endpoint:',
                  child: _PressedScale(
                    onTap:
                        () => _copy(
                          context,
                          'paperstudio.onrender.com',
                          'Endpoint copied',
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'paperstudio.onrender.com',
                            style: _DeploymentText.caption(
                              color: _DeploymentColors.secondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: _DeploymentColors.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(this.label, {this.background, this.foreground});

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? _DeploymentColors.surfaceVariant,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: _DeploymentText.caption(
          color: foreground ?? _DeploymentColors.onSurface,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const foreground = _DeploymentColors.onPrimary;

    return _PressedScale(
      onTap: busy ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: _DeploymentColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 17, color: foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: _DeploymentText.bodyMd(
                  color: foreground,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: _DeploymentText.caption(color: _DeploymentColors.outline),
        ),
        const SizedBox(width: 12),
        Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
      ],
    );
  }
}

class _InactivityBanner extends StatelessWidget {
  const _InactivityBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DeploymentColors.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: _DeploymentColors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Free instances spin down after periods of inactivity, '
                  'which may delay new requests by 50 seconds or more.',
                  style: _DeploymentText.bodySm(
                    color: _DeploymentColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                _PressedScale(
                  onTap: () {},
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Upgrade to Starter',
                        style: _DeploymentText.bodySm(
                          color: _DeploymentColors.onSurface,
                          weight: FontWeight.w700,
                        ).copyWith(decoration: TextDecoration.underline),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        size: 13,
                        color: _DeploymentColors.onSurface,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: _DeploymentText.bodySm(color: _DeploymentColors.onSurface),
      cursorColor: _DeploymentColors.primary,
      decoration: InputDecoration(
        hintText: 'Search deploys, authors, commits...',
        hintStyle: _DeploymentText.bodySm(color: _DeploymentColors.outline),
        filled: true,
        fillColor: _DeploymentColors.surfaceContainerHigh.withValues(
          alpha: 0.55,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        prefixIcon: const Icon(
          Icons.search,
          size: 19,
          color: _DeploymentColors.outline,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        suffixIcon: _PressedScale(
          onTap: () {
            controller.clear();
            onChanged('');
          },
          child: const Icon(
            Icons.close,
            size: 18,
            color: _DeploymentColors.outline,
          ),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'DEPLOYS',
          style: _DeploymentText.labelCaps(color: _DeploymentColors.onSurface),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _DeploymentColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            count.toString(),
            style: _DeploymentText.caption(
              color: _DeploymentColors.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        Text(
          'TRIGGER',
          style: _DeploymentText.labelCaps(color: _DeploymentColors.outline),
        ),
        const SizedBox(width: 26),
        Text(
          'DURATION',
          style: _DeploymentText.labelCaps(color: _DeploymentColors.outline),
        ),
      ],
    );
  }
}

class _DeployCard extends StatelessWidget {
  const _DeployCard({required this.item, required this.onTap});

  final _DeployItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final failed = item.state == _DeployState.failed;

    return _PressedScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _DeploymentColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _StatusCircle(state: item.state),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: _DeploymentText.bodySm(
                          color: _DeploymentColors.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.reference,
                              style: _DeploymentText.caption(
                                color:
                                    item.state == _DeployState.live
                                        ? _DeploymentColors.onSurface
                                        : _DeploymentColors.secondary,
                              ).copyWith(decoration: TextDecoration.underline),
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '•',
                            style: _DeploymentText.caption(
                              color: _DeploymentColors.outline,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            item.time,
                            style: _DeploymentText.caption(
                              color: _DeploymentColors.outline,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '•',
                            style: _DeploymentText.caption(
                              color: _DeploymentColors.outline,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              item.via,
                              style: _DeploymentText.caption(
                                color:
                                    failed
                                        ? _DeploymentColors.onSurface
                                        : _DeploymentColors.outline,
                                weight:
                                    failed ? FontWeight.w700 : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _DeploymentColors.surfaceContainerLowest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Flexible(child: _buildActions()),
                  const SizedBox(width: 8),
                  Text(
                    item.duration,
                    style: _DeploymentText.caption(
                      color: _DeploymentColors.outline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    failed ? Icons.bug_report : Icons.notes,
                    size: 15,
                    color:
                        failed
                            ? _DeploymentColors.danger
                            : _DeploymentColors.outline,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    switch (item.state) {
      case _DeployState.live:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _DeploymentColors.successGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'CURRENT LIVE',
              style: _DeploymentText.labelCaps(
                color: _DeploymentColors.successGreen,
              ),
            ),
          ],
        );
      case _DeployState.succeeded:
        return const _PillAction(icon: Icons.history, label: 'Rollback');
      case _DeployState.failed:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PillAction(icon: Icons.refresh, label: 'Retry'),
            SizedBox(width: 8),
            _PillAction(label: 'View failure'),
          ],
        );
    }
  }
}

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.state});

  final _DeployState state;

  @override
  Widget build(BuildContext context) {
    final (Color background, Widget icon) = switch (state) {
      _DeployState.live => (
        _DeploymentColors.successGreen,
        const Icon(Icons.check, size: 14, color: _DeploymentColors.primary),
      ),
      _DeployState.succeeded => (
        _DeploymentColors.surfaceContainerHigh,
        const Icon(
          Icons.check_circle_outline,
          size: 17,
          color: _DeploymentColors.onSurfaceVariant,
        ),
      ),
      _DeployState.failed => (
        _DeploymentColors.danger,
        const Icon(Icons.cancel, size: 15, color: _DeploymentColors.primary),
      ),
    };

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: icon,
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _DeploymentColors.surfaceContainerLowest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _DeploymentColors.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: _DeploymentColors.onSurface),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: _DeploymentText.caption(color: _DeploymentColors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: _DeploymentColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'No deploys match "$query"',
        textAlign: TextAlign.center,
        style: _DeploymentText.bodySm(
          color: _DeploymentColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TerminalHealth extends StatelessWidget {
  const _TerminalHealth();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DeploymentColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'BUILDIFY ENGINE',
                style: _DeploymentText.labelCaps(
                  color: _DeploymentColors.outline,
                ),
              ),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _DeploymentColors.successGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Clusters operational',
                style: _DeploymentText.caption(
                  color: _DeploymentColors.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 94,
                    child: ColoredBox(color: _DeploymentColors.successGreen),
                  ),
                  Expanded(
                    flex: 6,
                    child: ColoredBox(color: _DeploymentColors.danger),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Auto-deploy: Enabled',
                style: _DeploymentText.bodySm(color: _DeploymentColors.outline),
              ),
              const Spacer(),
              Text(
                'Region: oregon-us-west',
                style: _DeploymentText.bodySm(color: _DeploymentColors.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DeployState { live, succeeded, failed }

class _DeployItem {
  const _DeployItem({
    required this.state,
    required this.title,
    required this.reference,
    required this.time,
    required this.via,
    required this.duration,
  });

  final _DeployState state;
  final String title;
  final String reference;
  final String time;
  final String via;
  final String duration;

  String get searchText => '$title $reference $via $time';
}

const List<_DeployItem> _items = [
  _DeployItem(
    state: _DeployState.live,
    title:
        'Merge pull request #30 from Sujith8257/2026-03-06-snud-9232c '
        'Refactor LanderPage, Terminal Glass UI',
    reference: 'b3dd324',
    time: '7mo ago',
    via: 'push',
    duration: '7m 37s',
  ),
  _DeployItem(
    state: _DeployState.succeeded,
    title:
        'Merge pull request #29 from Sujith8257/2026-03-06-snud-9232c '
        '2026 03 06 snud 9232c',
    reference: 'f35e660',
    time: '8mo ago',
    via: 'manual',
    duration: '3m 36s',
  ),
  _DeployItem(
    state: _DeployState.succeeded,
    title:
        'Merge pull request #28 from Sujith8257/2026-03-06-snud-9232c '
        'Refactor error handling in Lander',
    reference: 'df2a4ea',
    time: '8mo ago',
    via: 'push',
    duration: '2m 57s',
  ),
  _DeployItem(
    state: _DeployState.failed,
    title: 'fix: environment config and docker build step [exit 1]',
    reference: 'a18c992',
    time: '8mo ago',
    via: 'Build failed',
    duration: '1m 12s',
  ),
];

class _DeploymentColors {
  static const Color surface = Color(0xFF131312);
  static const Color onSurface = Color(0xFFE5E2E0);
  static const Color onSurfaceVariant = Color(0xFFC4C7C8);
  static const Color surfaceContainerLowest = Color(0xFF0E0E0D);
  static const Color surfaceContainerLow = Color(0xFF1C1C1A);
  static const Color surfaceContainerHigh = Color(0xFF2A2A29);
  static const Color surfaceVariant = Color(0xFF353533);
  static const Color outline = Color(0xFF8E9192);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFF2F3131);
  static const Color secondary = Color(0xFFC8C6C3);
  static const Color secondaryContainer = Color(0xFF474744);
  static const Color onSecondaryContainer = Color(0xFFB7B5B1);
  static const Color successGreen = Color(0xFF10B981);
  static const Color danger = Color(0xFFE5484D);
}

class _DeploymentText {
  static TextStyle caption({Color? color, FontWeight? weight}) =>
      GoogleFonts.spaceMono(
        fontSize: 11,
        height: 15 / 11,
        fontWeight: weight ?? FontWeight.w400,
        color: color,
      );
  static TextStyle bodySm({Color? color, FontWeight? weight}) =>
      GoogleFonts.spaceMono(
        fontSize: 12,
        height: 17 / 12,
        fontWeight: weight ?? FontWeight.w400,
        color: color,
      );
  static TextStyle bodyMd({Color? color, FontWeight? weight}) =>
      GoogleFonts.spaceMono(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: weight ?? FontWeight.w400,
        color: color,
      );
  static TextStyle headlineMd({Color? color}) => GoogleFonts.spaceMono(
    fontSize: 18,
    height: 24 / 18,
    letterSpacing: -0.36,
    fontWeight: FontWeight.w700,
    color: color,
  );
  static TextStyle headlineLg({Color? color}) => GoogleFonts.spaceMono(
    fontSize: 20,
    height: 26 / 20,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w700,
    color: color,
  );
  static TextStyle labelCaps({Color? color}) => GoogleFonts.spaceMono(
    fontSize: 10,
    height: 12 / 10,
    letterSpacing: 1,
    fontWeight: FontWeight.w700,
    color: color,
  );
}

class _PressedScale extends StatefulWidget {
  const _PressedScale({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressedScale> createState() => _PressedScaleState();
}

class _PressedScaleState extends State<_PressedScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Transform.scale(scale: _pressed ? 0.98 : 1, child: widget.child),
    );
  }
}
