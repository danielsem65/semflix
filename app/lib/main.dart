import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const String kPlaylistUrl = 'https://iptv-org.github.io/iptv/index.m3u';
const String kLastChannelKey = 'semflix_last_channel';

class Channel {
  final String name;
  final String logo;
  final String group;
  final String url;
  Channel({required this.name, required this.logo, required this.group, required this.url});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    await _initWindowChrome();
  }
  runApp(const SemFlixApp());
}

Future<void> _initWindowChrome() async {
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    size: const Size(1280, 720),
    center: true,
    title: 'SemFlix TV',
    backgroundColor: const Color(0xFF05060A),
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: false,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
  });
}

class SemFlixApp extends StatelessWidget {
  const SemFlixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SemFlix TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFF2E63),
          secondary: const Color(0xFF00F0FF),
          surface: const Color(0xFF0B0E16),
        ),
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      body: Stack(
        children: [
          Center(
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutBack,
              ),
              child: FadeTransition(
                opacity: _controller,
                child: Image.asset(
                  'assets/icon/logo.png',
                  width: 190,
                  height: 190,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 42,
            child: Column(
              children: const [
                Text(
                  'SemDev Studio',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'v1.0.0',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Channel> _channels = [];
  List<Channel> _filtered = [];
  List<String> _cats = ['All'];
  String _activeCat = 'All';
  String _query = '';

  bool _loading = true;
  String? _error;

  Channel? _current;
  bool _buffering = false;

  late final Player _player;
  late final VideoController _controller;
  final _searchCtrl = TextEditingController();
  final _sidebarScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });

    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sidebarScroll.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await http
          .get(Uri.parse(kPlaylistUrl), headers: {'accept': 'text/plain'})
          .timeout(const Duration(seconds: 40))
          .then((r) => r.body);

      final parsed = _parseM3U(text);

      if (!mounted) return;
      setState(() {
        _channels = parsed;
        _filtered = parsed;
        _cats = _buildCats(parsed);
        _loading = false;
      });

      final saved = await _lastSavedUrl();
      final target =
          saved != null ? parsed.where((c) => c.url == saved).toList() : <Channel>[];
      if (target.isNotEmpty) {
        _play(target.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load playlist. Check your connection.';
      });
    }
  }

  List<String> _buildCats(List<Channel> channels) {
    final map = <String, int>{};
    for (final c in channels) {
      map[c.group] = (map[c.group] ?? 0) + 1;
    }
    final keys = map.keys.toList()
      ..sort((a, b) => (map[b] ?? 0).compareTo(map[a] ?? 0));
    return ['All', ...keys.take(30)];
  }

  List<Channel> _parseM3U(String text) {
    final out = <Channel>[];
    final lines = text.split('\n');
    String? name, logo, group, url;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXTINF')) {
        name = line.split(',').last.trim();
        logo = _attr(line, 'tvg-logo');
        group = _attr(line, 'group-title');
        url = null;
      } else if (line.startsWith('http')) {
        url = line;
        if (name != null && url != null) {
          out.add(Channel(
            name: name,
            logo: logo ?? '',
            group: group == null || group.isEmpty ? 'General' : group,
            url: url,
          ));
          name = null;
        }
      }
    }
    return out;
  }

  String? _attr(String line, String key) {
    final m = RegExp('$key="([^"]*)"').firstMatch(line);
    return m?.group(1);
  }

  Future<String?> _lastSavedUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kLastChannelKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(Channel c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLastChannelKey, c.url);
    } catch (_) {}
  }

  void _play(Channel c) {
    _remember(c);
    setState(() {
      _current = c;
      _buffering = true;
    });
    _player.open(Media(c.url));
    _player.play();
  }

  void _filter() {
    final q = _query.toLowerCase();
    final list = _channels.where((c) {
      final catOk = _activeCat == 'All' || c.group == _activeCat;
      final qOk = q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          c.group.toLowerCase().contains(q);
      return catOk && qOk;
    }).toList();
    setState(() => _filtered = list);
  }

  void _openMobileDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0E16),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (_, sheetSetState) => FractionallySizedBox(
          heightFactor: 0.86,
          child: _buildSidebar(
            compact: true,
            refresh: () => sheetSetState(() {}),
            scrollController: _sidebarScroll,
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentChannel();
      if (_current != null && !_sidebarScroll.hasClients) {
        Future.delayed(const Duration(milliseconds: 150),
            () => _scrollToCurrentChannel());
      }
    });
  }

  void _scrollToCurrentChannel() {
    if (_current == null || !_sidebarScroll.hasClients) return;
    final idx = _filtered.indexWhere((c) => c.url == _current!.url);
    if (idx < 0) return;
    final target = (idx * 68.0) - 140;
    final max = _sidebarScroll.position.maxScrollExtent;
    _sidebarScroll.jumpTo(target.clamp(0.0, max).toDouble());
  }

  Widget _buildSidebar({
    bool compact = false,
    VoidCallback? refresh,
    ScrollController? scrollController,
  }) {
    return Column(
      children: [
        if (compact)
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) {
              _query = v.trim();
              _filter();
              refresh?.call();
            },
            decoration: InputDecoration(
              hintText: 'Search channels...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0x0DFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _cats.map((c) {
              final active = c == _activeCat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c),
                  selected: active,
                  onSelected: (_) {
                    setState(() => _activeCat = c);
                    _filter();
                    refresh?.call();
                  },
                  selectedColor: const Color(0xFFFF2E63),
                  backgroundColor: const Color(0x0DFFFFFF),
                  labelStyle: TextStyle(
                    color: active ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: active ? const Color(0xFFFF2E63) : Colors.white12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(
                  child: Text('No channels found',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemExtent: 68,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final c = _filtered[i];
                    final selected = _current?.url == c.url;
                    return _ChannelTile(
                      channel: c,
                      selected: selected,
                      onTap: () {
                        if (compact) Navigator.of(context).pop();
                        _play(c);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlayer() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: Video(controller: _controller)),
          if (_current != null)
            Positioned(
              top: 12,
              left: 12,
              child: _LiveBadge(),
            ),
          if (_current != null)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _current!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (_buffering && _current != null)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFFFF2E63)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return Row(
                  children: [
                    if (wide)
                      SizedBox(
                        width: 360,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0B0E16),
                          ),
                          child: _buildSidebar(),
                        ),
                      ),
                    Expanded(
                      child: _buildMainZone(context, wide),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainZone(BuildContext context, bool wide) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFFFF2E63)),
            ),
            SizedBox(height: 16),
            Text('Loading IPTV Playlist...',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2E63),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: _buildPlayer()),
        if (!wide)
          Container(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openMobileDrawer(context),
                icon: const Icon(Icons.grid_view),
                label: const Text('Browse Channels'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2E63),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    final count = _channels.length;
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0E16),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x33FF2E63),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/icon/icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.play_arrow, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('SemFlix TV',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5)),
              Text('Free IPTV Streaming',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const Spacer(),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count Channels',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
          const SizedBox(width: 8),
          const _LiveBadge(),
          if (Platform.isWindows) ...[
            const SizedBox(width: 10),
            const _WindowButtons(),
          ],
        ],
      ),
    );
    if (!Platform.isWindows) return header;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: header,
    );
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> {
  bool _maximized = false;
  late final WindowListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = _MaximizeListener(this);
    windowManager.addListener(_listener);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          onTap: () {
            if (_maximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
        ),
        const SizedBox(width: 2),
        _WindowButton(icon: Icons.close, onTap: () => windowManager.close()),
      ],
    );
  }
}

class _MaximizeListener extends WindowListener {
  _MaximizeListener(this.state);

  final _WindowButtonsState state;

  @override
  void onWindowMaximize() {
    if (state.mounted) state.setState(() => state._maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (state.mounted) state.setState(() => state._maximized = false);
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: Colors.grey),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: .7,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x26FF2E63),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x80FF2E63)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _ctrl,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFFFF2E63),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Color(0xFFFF5C7E),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool selected;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Material(
        color: selected
            ? const Color(0x1FFF2E63)
            : const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF2E63)),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 46,
                    height: 46,
                    color: Colors.white,
                    child: Image.network(
                      channel.logo,
                      fit: BoxFit.contain,
                      width: 46,
                      height: 46,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.tv, color: Colors.black38, size: 22),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        channel.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
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
