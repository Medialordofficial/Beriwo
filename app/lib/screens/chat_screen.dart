import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:html' as html;
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/dashboard_service.dart';
import '../models/chat_message.dart';

const _blue = Color(0xFF1976D2);
const _navy = Color(0xFF1B3A5C);
const _gold = Color(0xFFC5A55A);
const _bg = Color(0xFFF9FAFC);
const _surface = Colors.white;
const _textPrimary = Color(0xFF202124);
const _textSecondary = Color(0xFF5F6368);
const _border = Color(0xFFE8EAED);
const _green = Color(0xFF34A853);
const _orange = Color(0xFFFBBC05);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  int _sidebarIndex = 0;
  int _emailTab = 0;
  bool _autoPilot = true;
  bool _dataLoaded = false;
  bool _chatOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _emailSearchController = TextEditingController();
  final TextEditingController _fileSearchController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void dispose() {
    _chatController.dispose();
    _emailSearchController.dispose();
    _fileSearchController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    if (_dataLoaded) return;
    final auth = context.read<AuthService>();
    if (auth.isLoggedIn && auth.accessToken != null) {
      _dataLoaded = true;
      context.read<DashboardService>().loadDashboard(auth.accessToken);
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final dash = context.watch<DashboardService>();
    final chat = context.watch<ChatService>();
    if (auth.isLoggedIn && !_dataLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    }
    // Auto-scroll chat when messages change
    if (_chatOpen && chat.messages.isNotEmpty) {
      _scrollChatToBottom();
    }
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildTopNav(auth),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebar(dash),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24.0),
                          child: _buildMainContent(dash, auth),
                        ),
                      ),
                      _buildBottomBar(auth),
                    ],
                  ),
                ),
                if (_chatOpen) _buildChatPanel(chat, auth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _buildTopNav(AuthService auth) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Row(children: [const _BeriwoLogo(fontSize: 24)]),
          const SizedBox(width: 32),
          const Text(
            'Your Autonomous AI Operator',
            style: TextStyle(color: _textSecondary, fontSize: 14),
          ),
          const Spacer(),
          Text(
            '${_getGreeting()}, ${auth.user?.name?.split(' ').first ?? 'User'},',
            style: const TextStyle(fontSize: 14, color: _textPrimary),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              switch (value) {
                case 'signout':
                  auth.logout();
                  break;
                case 'profile':
                  setState(() => _sidebarIndex = 5);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user?.name ?? 'User',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auth.user?.email ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: _textSecondary,
                    ),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: Colors.redAccent),
                    SizedBox(width: 12),
                    Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _blue.withOpacity(0.1),
                  backgroundImage: auth.user?.pictureUrl != null
                      ? NetworkImage(auth.user!.pictureUrl.toString())
                      : null,
                  child: auth.user?.pictureUrl == null
                      ? const Icon(Icons.person, size: 20, color: _blue)
                      : null,
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_arrow_down, color: _textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(DashboardService dash) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _SidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            selected: _sidebarIndex == 0,
            onTap: () => setState(() => _sidebarIndex = 0),
          ),
          _SidebarItem(
            icon: Icons.mail_outline_rounded,
            label: 'Inbox',
            selected: _sidebarIndex == 1 && _emailTab == 0,
            color: Colors.redAccent,
            badge: dash.unreadCount > 0 ? dash.unreadCount : null,
            onTap: () {
              setState(() {
                _sidebarIndex = 1;
                _emailTab = 0;
              });
              final auth = context.read<AuthService>();
              dash.loadEmails(auth.accessToken);
            },
          ),
          _SidebarItem(
            icon: Icons.send_outlined,
            label: 'Sent',
            selected: _sidebarIndex == 1 && _emailTab == 1,
            color: Colors.teal,
            badge: dash.sentCount > 0 ? dash.sentCount : null,
            onTap: () {
              setState(() {
                _sidebarIndex = 1;
                _emailTab = 1;
              });
              final auth = context.read<AuthService>();
              dash.loadEmails(auth.accessToken, label: 'SENT');
            },
          ),
          _SidebarItem(
            icon: Icons.meeting_room_outlined,
            label: 'Meetings',
            selected: _sidebarIndex == 2,
            color: Colors.blue,
            badge: dash.todayEventCount > 0 ? dash.todayEventCount : null,
            onTap: () {
              setState(() => _sidebarIndex = 2);
              final auth = context.read<AuthService>();
              dash.loadEvents(auth.accessToken);
            },
          ),
          _SidebarItem(
            icon: Icons.work_outline_rounded,
            label: 'Projects',
            selected: _sidebarIndex == 3,
            color: Colors.blueAccent,
            onTap: () {
              setState(() => _sidebarIndex = 3);
              final auth = context.read<AuthService>();
              dash.loadFiles(auth.accessToken);
            },
          ),
          _SidebarItem(
            icon: Icons.description_outlined,
            label: 'Docs',
            selected: _sidebarIndex == 4,
            color: Colors.blueGrey,
            onTap: () {
              setState(() => _sidebarIndex = 4);
              final auth = context.read<AuthService>();
              dash.loadFiles(auth.accessToken);
            },
          ),
          _SidebarItem(
            icon: Icons.settings_outlined,
            label: 'Preferences',
            selected: _sidebarIndex == 5,
            color: Colors.grey,
            onTap: () => setState(() => _sidebarIndex = 5),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.psychology,
                  size: 16,
                  color: _autoPilot ? _green : _textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  _autoPilot ? 'Active Mode: Auto Pilot' : 'Mode: Manual',
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Text(
                    'Auto Pilot',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _autoPilot,
                    onChanged: (v) {
                      setState(() => _autoPilot = v);
                      _toggleAutoPilot(v);
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: _blue.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _toggleAutoPilot(bool enabled) async {
    final auth = context.read<AuthService>();
    final dash = context.read<DashboardService>();
    if (auth.accessToken == null) return;
    final success = await dash.toggleAutoPilot(auth.accessToken, enabled);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Auto Pilot enabled' : 'Switched to Manual mode',
          ),
          backgroundColor: enabled ? _green : _navy,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Revert the toggle on failure
      setState(() => _autoPilot = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update Auto Pilot setting'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildMainContent(DashboardService dash, AuthService auth) {
    if (dash.loading && !dash.connected && dash.emails.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(64),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (dash.error != null && dash.emails.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                dash.error!,
                style: const TextStyle(color: _textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _dataLoaded = false;
                  _loadData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    switch (_sidebarIndex) {
      case 0:
        return _buildDashboard(dash);
      case 1:
        return _buildInbox(dash, auth);
      case 2:
        return _buildMeetings(dash, auth);
      case 3:
        return _buildProjects(dash);
      case 4:
        return _buildDocs(dash, auth);
      case 5:
        return _buildPreferences(auth);
      default:
        return _buildDashboard(dash);
    }
  }

  // ─── DASHBOARD TAB ───
  Widget _buildDashboard(DashboardService dash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildBriefingCard(dash)),
            const SizedBox(width: 24),
            Expanded(child: _buildRecentFilesCard(dash)),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLiveActionsCard(dash)),
            const SizedBox(width: 24),
            Expanded(child: _buildUpcomingEventsCard(dash)),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildRecentEmailsCard(dash)),
            const SizedBox(width: 24),
            Expanded(child: _buildAgentAssistantsCard(dash)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCardBase(
    String title,
    List<Widget> children, {
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right, color: _textSecondary),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildBriefingCard(DashboardService dash) {
    final unread = dash.unreadCount;
    final meetings = dash.todayEventCount;
    final files = dash.files.length;
    return _buildCardBase("Today's Briefing", [
      _ActionItem(
        icon: Icons.mail,
        iconColor: Colors.redAccent,
        text: '$unread Unread Email${unread == 1 ? '' : 's'}',
        bold: true,
      ),
      _ActionItem(
        icon: Icons.calendar_today,
        iconColor: _blue,
        text: '$meetings Meeting${meetings == 1 ? '' : 's'} Today',
        bold: true,
      ),
      _ActionItem(
        icon: Icons.folder,
        iconColor: _orange,
        text: '$files Recent File${files == 1 ? '' : 's'}',
        bold: true,
      ),
      if (dash.loading)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      const SizedBox(height: 16),
      Center(
        child: OutlinedButton(
          onPressed: () => setState(() => _sidebarIndex = 1),
          child: const Text('View Inbox >'),
        ),
      ),
    ]);
  }

  Widget _buildRecentFilesCard(DashboardService dash) {
    final topFiles = dash.files.take(3).toList();
    return _buildCardBase(
      "Recent Documents",
      [
        if (topFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'No recent files',
              style: TextStyle(color: _textSecondary),
            ),
          )
        else
          ...topFiles.map(
            (f) => _ActionItem(
              icon: _fileIcon(f.typeLabel),
              iconColor: _fileColor(f.typeLabel),
              text: f.name,
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: () => setState(() => _sidebarIndex = 4),
            child: const Text('View All Docs >'),
          ),
        ),
      ],
      trailing: const Icon(Icons.description_outlined, color: _blue),
    );
  }

  Widget _buildLiveActionsCard(DashboardService dash) {
    final acts = dash.activities.take(4).toList();
    return _buildCardBase("Live Actions", [
      if (acts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'No recent actions',
            style: TextStyle(color: _textSecondary),
          ),
        )
      else
        ...acts.map(
          (a) => _ActionItem(
            icon: a.status == 'done' ? Icons.check_circle : Icons.pending,
            iconColor: a.status == 'done' ? _green : _orange,
            text: a.detail.isNotEmpty ? a.detail : a.action,
            bold: a.status != 'done',
          ),
        ),
    ]);
  }

  Widget _buildUpcomingEventsCard(DashboardService dash) {
    final evts = dash.events.take(3).toList();
    return _buildCardBase(
      "Upcoming Events",
      [
        if (evts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'No events today',
              style: TextStyle(color: _textSecondary),
            ),
          )
        else
          ...evts.map(
            (e) => _ActionItem(
              icon: Icons.calendar_month,
              iconColor: _blue,
              text: '${e.summary} ${e.startTime}',
              bold: true,
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: () => setState(() => _sidebarIndex = 2),
            child: const Text('View All Meetings >'),
          ),
        ),
      ],
      trailing: const Icon(Icons.calendar_today_outlined, color: _blue),
    );
  }

  Widget _buildRecentEmailsCard(DashboardService dash) {
    final topEmails = dash.emails.take(3).toList();
    return _buildCardBase(
      "Recent Emails",
      [
        if (topEmails.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No emails', style: TextStyle(color: _textSecondary)),
          )
        else
          ...topEmails.map(
            (e) => _ActionItem(
              icon: e.unread ? Icons.mark_email_unread : Icons.mail_outline,
              iconColor: e.unread ? Colors.redAccent : _textSecondary,
              text: '${e.senderName}: ${e.subject}',
              bold: e.unread,
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: () => setState(() => _sidebarIndex = 1),
            child: const Text('View All Emails >'),
          ),
        ),
      ],
      trailing: const Icon(Icons.mail_outline, color: Colors.redAccent),
    );
  }

  Widget _buildAgentAssistantsCard(DashboardService dash) {
    return _buildCardBase("Agent Assistants", [
      Row(
        children: [
          Expanded(
            child: _AgentCard(
              icon: Icons.mail_outline,
              color: _green,
              title: 'Email Agent',
              subtitle: dash.emails.isNotEmpty
                  ? '${dash.unreadCount} unread'
                  : 'Idle',
              onTap: () =>
                  _sendToChat('Check my emails and summarize unread messages.'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AgentCard(
              icon: Icons.calendar_today,
              color: _blue,
              title: 'Schedule Agent',
              subtitle: dash.events.isNotEmpty
                  ? '${dash.todayEventCount} today'
                  : 'Idle',
              onTap: () => _sendToChat(
                'Check my calendar and brief me on upcoming meetings.',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _AgentCard(
              icon: Icons.description_outlined,
              color: Colors.cyan,
              title: 'Docs Agent',
              subtitle: dash.files.isNotEmpty
                  ? '${dash.files.length} files'
                  : 'Idle',
              onTap: () => _sendToChat('List my recent Google Drive files.'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AgentCard(
              icon: Icons.edit_outlined,
              color: _gold,
              title: 'Compose Agent',
              subtitle: 'Draft emails',
              onTap: () => _sendToChat('Help me compose a new email.'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _AgentCard(
              icon: Icons.reply_outlined,
              color: Colors.deepPurple,
              title: 'Reply Agent',
              subtitle: 'Smart replies',
              onTap: () => _sendToChat(
                'Show me emails that need a reply and suggest responses.',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AgentCard(
              icon: Icons.smart_toy_outlined,
              color: _autoPilot ? _green : Colors.grey,
              title: 'AutoPilot',
              subtitle: _autoPilot ? 'Active' : 'Off',
              onTap: () {
                setState(() => _autoPilot = !_autoPilot);
                _toggleAutoPilot(_autoPilot);
              },
            ),
          ),
        ],
      ),
    ], trailing: const Icon(Icons.psychology, color: _blue));
  }

  // ─── INBOX TAB ───
  Widget _buildInbox(DashboardService dash, AuthService auth) {
    final String tabTitle;
    final List<EmailItem> emailList;
    final bool isSentView;
    switch (_emailTab) {
      case 1:
        tabTitle = 'Sent';
        emailList = dash.sentEmails;
        isSentView = true;
        break;
      case 2:
        tabTitle = 'Business';
        emailList = dash.businessEmails;
        isSentView = false;
        break;
      default:
        tabTitle = 'Inbox';
        emailList = dash.emails;
        isSentView = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              tabTitle,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            if (_emailTab == 0 && dash.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${dash.unreadCount} unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_emailTab == 1)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${dash.sentCount} sent',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Spacer(),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _emailSearchController,
                decoration: InputDecoration(
                  hintText: 'Search emails...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
                onSubmitted: (q) {
                  if (_emailTab == 1) {
                    dash.loadEmails(auth.accessToken, query: q, label: 'SENT');
                  } else {
                    dash.loadEmails(auth.accessToken, query: q);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: _blue),
              onPressed: () {
                if (_emailTab == 1) {
                  dash.loadEmails(auth.accessToken, label: 'SENT');
                } else {
                  dash.loadEmails(auth.accessToken);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Sub-tabs: Inbox | Sent | Business
        Row(
          children: [
            _emailTabButton('Inbox', 0, Icons.inbox),
            const SizedBox(width: 8),
            _emailTabButton('Sent', 1, Icons.send),
            const SizedBox(width: 8),
            _emailTabButton('Business', 2, Icons.business),
          ],
        ),
        const SizedBox(height: 16),
        if (dash.loading) const LinearProgressIndicator(),
        if (!dash.connected && !dash.loading && emailList.isEmpty)
          _buildNotConnectedBanner(auth, 'emails')
        else if (emailList.isEmpty && !dash.loading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Text(
                'No $tabTitle emails found',
                style: const TextStyle(color: _textSecondary, fontSize: 16),
              ),
            ),
          )
        else
          ...emailList.map(
            (email) => _buildEmailTile(email, isSent: isSentView),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _emailTabButton(String label, int index, IconData icon) {
    final selected = _emailTab == index;
    return InkWell(
      onTap: () {
        setState(() => _emailTab = index);
        final auth = context.read<AuthService>();
        final dash = context.read<DashboardService>();
        if (index == 1) {
          dash.loadEmails(auth.accessToken, label: 'SENT');
        } else if (index == 0) {
          dash.loadEmails(auth.accessToken);
        }
        // Business tab filters in-memory from inbox, no extra load needed
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _blue : _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : _textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _textSecondary,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailTile(EmailItem email, {bool isSent = false}) {
    final displayName = isSent ? email.recipientName : email.senderName;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: email.unread ? _blue.withOpacity(0.04) : _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isSent
              ? Colors.teal
              : (email.unread ? _blue : Colors.grey.shade300),
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style: TextStyle(
              color: (isSent || email.unread) ? Colors.white : _textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                email.subject,
                style: TextStyle(
                  fontWeight: email.unread
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (email.isBusiness)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _navy.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Business',
                  style: TextStyle(
                    fontSize: 10,
                    color: _navy,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${isSent ? "To: " : ""}$displayName — ${email.snippet}',
          style: const TextStyle(fontSize: 12, color: _textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          email.shortDate,
          style: const TextStyle(fontSize: 11, color: _textSecondary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => _sendToChat(
          'Read email: "${email.subject}" from ${email.senderName}',
        ),
      ),
    );
  }

  // ─── MEETINGS TAB ───
  Widget _buildMeetings(DashboardService dash, AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Meetings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            if (dash.todayEventCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${dash.todayEventCount} upcoming',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, color: _blue),
              onPressed: () => dash.loadEvents(auth.accessToken),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (dash.loading) const LinearProgressIndicator(),
        if (!dash.connected && !dash.loading && dash.events.isEmpty)
          _buildNotConnectedBanner(auth, 'calendar')
        else if (dash.events.isEmpty && !dash.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Text(
                'No upcoming meetings',
                style: TextStyle(color: _textSecondary, fontSize: 16),
              ),
            ),
          )
        else
          ...dash.events.map((event) => _buildEventTile(event)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEventTile(EventItem event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 56,
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.summary,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 14,
                      color: _textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      event.timeRange,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                    ),
                    if (event.location.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: _textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          event.location,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (event.attendees.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.people, size: 14, color: _textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          event.attendees.take(3).join(', ') +
                              (event.attendees.length > 3
                                  ? ' +${event.attendees.length - 3}'
                                  : ''),
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, size: 20, color: _blue),
            tooltip: 'Ask Beriwo about this meeting',
            onPressed: () =>
                _sendToChat('Tell me about my meeting: "${event.summary}"'),
          ),
        ],
      ),
    );
  }

  // ─── PROJECTS TAB ───
  Widget _buildProjects(DashboardService dash) {
    // Group Drive folders as "projects"
    final folders = dash.files.where((f) => f.typeLabel == 'Folder').toList();
    final docs = dash.files.where((f) => f.typeLabel != 'Folder').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Projects',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Organized from your Google Drive folders and recent activity.',
          style: TextStyle(color: _textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (folders.isNotEmpty) ...[
          const Text(
            'Folders',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: folders.map((f) => _buildProjectCard(f)).toList(),
          ),
          const SizedBox(height: 24),
        ],
        const Text(
          'Recent Files',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (docs.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Text('No files', style: TextStyle(color: _textSecondary)),
            ),
          )
        else
          ...docs.take(10).map((f) => _buildFileTile(f)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProjectCard(FileItem folder) {
    return InkWell(
      onTap: () {
        if (folder.webViewLink.isNotEmpty) {
          html.window.open(folder.webViewLink, '_blank');
        }
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.folder, size: 32, color: _orange),
            const SizedBox(height: 8),
            Text(
              folder.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              folder.shortDate,
              style: const TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DOCS TAB ───
  Widget _buildDocs(DashboardService dash, AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Documents',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${dash.files.length} files',
                style: const TextStyle(
                  color: _blue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _fileSearchController,
                decoration: InputDecoration(
                  hintText: 'Search files...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
                onSubmitted: (q) => dash.loadFiles(auth.accessToken, query: q),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: _blue),
              onPressed: () => dash.loadFiles(auth.accessToken),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (dash.loading) const LinearProgressIndicator(),
        if (!dash.connected && !dash.loading && dash.files.isEmpty)
          _buildNotConnectedBanner(auth, 'files')
        else if (dash.files.isEmpty && !dash.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Text(
                'No files found',
                style: TextStyle(color: _textSecondary, fontSize: 16),
              ),
            ),
          )
        else
          ...dash.files.map((file) => _buildFileTile(file)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFileTile(FileItem file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          _fileIcon(file.typeLabel),
          color: _fileColor(file.typeLabel),
          size: 28,
        ),
        title: Text(
          file.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${file.typeLabel} · Modified ${file.shortDate}',
          style: const TextStyle(fontSize: 12, color: _textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (file.webViewLink.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18, color: _blue),
                tooltip: 'Open in Drive',
                onPressed: () => html.window.open(file.webViewLink, '_blank'),
              ),
            IconButton(
              icon: const Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: _textSecondary,
              ),
              tooltip: 'Ask Beriwo about this file',
              onPressed: () => _sendToChat('Summarize my file: "${file.name}"'),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  // ─── PREFERENCES TAB ───
  Widget _buildPreferences(AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preferences',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _buildCardBase('Auto Pilot', [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Autonomous Mode',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _autoPilot
                          ? 'Beriwo will automatically handle emails, schedule meetings, and manage your tasks.'
                          : 'Beriwo will ask for your approval before taking any actions.',
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoPilot,
                onChanged: (v) => setState(() => _autoPilot = v),
                activeThumbColor: _blue,
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),
        _buildCardBase('Account', [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: _blue.withOpacity(0.1),
              backgroundImage: auth.user?.pictureUrl != null
                  ? NetworkImage(auth.user!.pictureUrl.toString())
                  : null,
              child: auth.user?.pictureUrl == null
                  ? const Icon(Icons.person, color: _blue)
                  : null,
            ),
            title: Text(
              auth.user?.name ?? 'User',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              auth.user?.email ?? '',
              style: const TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ),
          const Divider(),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link, color: _green),
            title: Text(
              'Google Account',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Connected via Auth0',
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
            trailing: Icon(Icons.check_circle, color: _green, size: 20),
          ),
        ]),
        const SizedBox(height: 16),
        _buildCardBase('Connected Services', [
          _ServiceTile(
            icon: Icons.mail,
            color: Colors.redAccent,
            name: 'Gmail',
            status: 'Connected',
          ),
          _ServiceTile(
            icon: Icons.calendar_today,
            color: _blue,
            name: 'Google Calendar',
            status: 'Connected',
          ),
          _ServiceTile(
            icon: Icons.folder,
            color: _orange,
            name: 'Google Drive',
            status: 'Connected',
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── BOTTOM BAR ───
  Widget _buildBottomBar(AuthService auth) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _blue.withOpacity(0.1),
            backgroundImage: auth.user?.pictureUrl != null
                ? NetworkImage(auth.user!.pictureUrl.toString())
                : null,
            child: auth.user?.pictureUrl == null
                ? const Icon(Icons.person, color: _blue, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'What can I handle for you next?',
                hintStyle: const TextStyle(color: _textSecondary),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _border),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: _blue, size: 20),
                  onPressed: () {
                    if (_chatController.text.trim().isNotEmpty) {
                      _sendToChat(_chatController.text.trim());
                      _chatController.clear();
                    }
                  },
                ),
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) {
                  _sendToChat(text.trim());
                  _chatController.clear();
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _sendToChat(
              'Triage my day — check emails, calendar, and files, then brief me.',
            ),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text(
              'Run Mission',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _sendToChat(String message) {
    final auth = context.read<AuthService>();
    final chat = context.read<ChatService>();
    if (auth.accessToken == null) return;
    setState(() => _chatOpen = true);
    chat.sendStreaming(
      message,
      auth.refreshToken ?? '',
      accessToken: auth.accessToken,
    );
  }

  // ─── NOT CONNECTED BANNER ───
  Widget _buildNotConnectedBanner(AuthService auth, String dataType) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: _orange.withOpacity(0.7)),
            const SizedBox(height: 16),
            const Text(
              'Unable to access your Google data',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Beriwo needs access to your Google account to show your $dataType. '
              'Try signing out and back in to refresh the connection.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  onPressed: () {
                    _dataLoaded = false;
                    _loadData();
                  },
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign Out & Reconnect'),
                  onPressed: () => auth.logout(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── CHAT PANEL ───
  Widget _buildChatPanel(ChatService chat, AuthService auth) {
    return Container(
      width: 420,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(left: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Chat header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.psychology, color: _blue, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Ber!wo Agent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                if (chat.currentPhase != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      chat.currentPhase!,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: _textSecondary,
                  ),
                  tooltip: 'Clear chat',
                  onPressed: () {
                    chat.clearChat();
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: _textSecondary,
                  ),
                  tooltip: 'Close chat',
                  onPressed: () => setState(() => _chatOpen = false),
                ),
              ],
            ),
          ),
          // Messages list
          Expanded(
            child: chat.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: _border,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Ask Beriwo anything about your emails, calendar, or files.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: chat.messages.length + (chat.sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == chat.messages.length) {
                        // Typing indicator
                        return _buildTypingIndicator(chat);
                      }
                      return _buildMessageBubble(
                        chat.messages[index],
                        chat,
                        auth,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ChatService chat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundColor: _navy,
            child: Text(
              'B',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  _phaseLabel(chat.currentPhase),
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(String? phase) {
    switch (phase) {
      case 'planning':
        return 'Planning actions...';
      case 'executing':
        return 'Executing tools...';
      case 'reflecting':
        return 'Reflecting on results...';
      case 'synthesizing':
        return 'Composing response...';
      default:
        return 'Thinking...';
    }
  }

  Widget _buildMessageBubble(
    ChatMessage msg,
    ChatService chat,
    AuthService auth,
  ) {
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  msg.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: _blue.withOpacity(0.1),
              backgroundImage: auth.user?.pictureUrl != null
                  ? NetworkImage(auth.user!.pictureUrl.toString())
                  : null,
              child: auth.user?.pictureUrl == null
                  ? const Icon(Icons.person, size: 14, color: _blue)
                  : null,
            ),
          ],
        ),
      );
    }

    // Bot message
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundColor: _navy,
            child: Text(
              'B',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phase indicator
                if (msg.phases != null) _buildPhaseIndicator(msg.phases!),
                // Execution steps
                if (msg.executionSteps.isNotEmpty)
                  _buildExecutionSteps(msg.executionSteps),
                // Message text
                if (msg.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: SelectableText(
                      msg.text,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                // Tools used
                if (msg.toolsUsed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: msg.toolsUsed
                          .map(
                            (t) => Chip(
                              label: Text(
                                t,
                                style: const TextStyle(fontSize: 10),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              backgroundColor: _blue.withOpacity(0.08),
                              side: BorderSide.none,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                // Blocked writes needing consent
                if (msg.blockedWrites.isNotEmpty)
                  _buildConsentCard(msg, chat, auth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseIndicator(AgentPhases phases) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          _phaseChip('Plan', phases.planned),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 14, color: _textSecondary),
          const SizedBox(width: 4),
          _phaseChip('Execute', phases.executed),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 14, color: _textSecondary),
          const SizedBox(width: 4),
          _phaseChip('Synthesize', phases.synthesized),
        ],
      ),
    );
  }

  Widget _phaseChip(String label, bool done) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: done ? _green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            const Icon(Icons.check_circle, size: 12, color: _green)
          else
            Icon(Icons.circle_outlined, size: 12, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: done ? _green : _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionSteps(List<ExecutionStep> steps) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps
            .map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      step.status == 'done'
                          ? Icons.check_circle
                          : step.status == 'blocked'
                          ? Icons.block
                          : step.status == 'running'
                          ? Icons.sync
                          : Icons.circle_outlined,
                      size: 14,
                      color: step.status == 'done'
                          ? _green
                          : step.status == 'blocked'
                          ? Colors.redAccent
                          : _orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      step.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                    if (step.durationMs != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${step.durationMs}ms',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildConsentCard(
    ChatMessage msg,
    ChatService chat,
    AuthService auth,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield, size: 16, color: _orange),
              SizedBox(width: 6),
              Text(
                'Actions need your approval',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...msg.blockedWrites.map(
            (bw) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 14, color: _textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${bw.label}${bw.purpose != null ? ' — ${bw.purpose}' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approve'),
                onPressed: () {
                  // Approve consented writes — pass tool names so backend allows them
                  final toolNames = msg.blockedWrites
                      .map((bw) => bw.tool)
                      .toList();
                  if (auth.accessToken != null) {
                    chat.sendStreaming(
                      'I approve the pending actions',
                      auth.refreshToken ?? '',
                      accessToken: auth.accessToken,
                      approvedWrites: toolNames,
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Deny'),
                onPressed: () {
                  chat.clearInterrupt('The actions were denied by the user.');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ───
  IconData _fileIcon(String typeLabel) {
    switch (typeLabel) {
      case 'Document':
        return Icons.article;
      case 'Spreadsheet':
        return Icons.table_chart;
      case 'Presentation':
        return Icons.slideshow;
      case 'PDF':
        return Icons.picture_as_pdf;
      case 'Image':
        return Icons.image;
      case 'Folder':
        return Icons.folder;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String typeLabel) {
    switch (typeLabel) {
      case 'Document':
        return _blue;
      case 'Spreadsheet':
        return _green;
      case 'Presentation':
        return _orange;
      case 'PDF':
        return Colors.redAccent;
      case 'Image':
        return Colors.purple;
      case 'Folder':
        return _orange;
      default:
        return _textSecondary;
    }
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color? color;
  final int? badge;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? _blue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: selected ? _blue : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : (color ?? _textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? _blue : _textPrimary,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool bold;

  const _ActionItem({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _AgentCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.play_circle_outline,
                color: _textSecondary,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String status;

  const _ServiceTile({
    required this.icon,
    required this.color,
    required this.name,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: _green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BeriwoLogo extends StatelessWidget {
  final double fontSize;
  const _BeriwoLogo({this.fontSize = 24});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFamily: 'Georgia',
          letterSpacing: 0.5,
        ),
        children: const [
          TextSpan(
            text: 'Ber',
            style: TextStyle(color: _navy),
          ),
          TextSpan(
            text: '!',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: 'wo',
            style: TextStyle(color: _navy),
          ),
        ],
      ),
    );
  }
}
