import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/notibar_bloc.dart';
import '../bloc/notibar_event.dart';
import '../bloc/notibar_state.dart';
import '../models/account.dart';
import '../models/notification_option.dart';
import '../services/outlook_auth_service.dart';
import '../plugins/plugin_interface.dart';
import '../plugins/microsoft/microsoft_plugin.dart';

// ─── Helpers ──────────────────────────────────────────────────────

/// Look up plugin-provided data via the bloc's plugin map.
NotibarPlugin? _pluginFor(
  Map<ServiceType, NotibarPlugin> plugins,
  ServiceType type,
) => plugins[type];

String _serviceLabel(
  Map<ServiceType, NotibarPlugin> plugins,
  ServiceType type,
) => _pluginFor(plugins, type)?.serviceLabel ?? type.name;

IconData _serviceIcon(
  Map<ServiceType, NotibarPlugin> plugins,
  ServiceType type,
) => _pluginFor(plugins, type)?.serviceIcon ?? Icons.notifications;

List<MetricDefinition> _supportedMetrics(
  Map<ServiceType, NotibarPlugin> plugins,
  ServiceType type,
) => _pluginFor(plugins, type)?.supportedMetrics ?? [];

Map<String, String> _configFields(
  Map<ServiceType, NotibarPlugin> plugins,
  ServiceType type,
) => _pluginFor(plugins, type)?.configFields ?? {};

// ─── Main Settings Window ─────────────────────────────────────────

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key});

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Notibar Settings',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.view_list), text: 'Notifications'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Accounts'),
            ],
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_NotificationsTab(), _AccountsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  NOTIFICATIONS TAB — ordered list of tray items
// ════════════════════════════════════════════════════════════════════

class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotibarBloc, NotibarState>(
      builder: (context, state) {
        if (state is! NotibarLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // Add button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    'These items appear in your menu bar, in this order.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: state.accounts.isEmpty
                        ? null
                        : () => _showAddOptionDialog(context, state.accounts),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            // Option list
            Expanded(
              child: state.options.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.view_list,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            state.accounts.isEmpty
                                ? 'Add an account first in the Accounts tab'
                                : 'Add a notification item to show in the tray',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      buildDefaultDragHandles: false,
                      itemCount: state.options.length,
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        context.read<NotibarBloc>().add(
                          ReorderNotificationOptions(oldIndex, newIndex),
                        );
                      },
                      itemBuilder: (context, index) {
                        final option = state.options[index];
                        final account = state.accounts
                            .where((a) => a.id == option.accountId)
                            .firstOrNull;
                        return _OptionCard(
                          key: ValueKey(option.id),
                          option: option,
                          account: account,
                          index: index,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showAddOptionDialog(BuildContext context, List<Account> accounts) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<NotibarBloc>(),
        child: _AddOptionDialog(accounts: accounts),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final NotificationOption option;
  final Account? account;
  final int index;

  const _OptionCard({
    super.key,
    required this.option,
    this.account,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<NotibarBloc>();
    final colorScheme = Theme.of(context).colorScheme;
    final plugin = account != null
        ? _pluginFor(bloc.plugins, account!.serviceType)
        : null;
    final metricDef = plugin?.metricById(option.metric);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: option.enabled ? 1 : 0,
      color: option.enabled
          ? null
          : colorScheme.surfaceContainerHighest.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.drag_indicator,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: option.enabled
                    ? colorScheme.primaryContainer
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                metricDef?.materialIcon ?? Icons.notifications,
                color: option.enabled ? colorScheme.primary : Colors.grey,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account?.name ?? 'Unknown account',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: option.enabled ? null : Colors.grey,
                    ),
                  ),
                  Text(
                    metricDef?.label ?? option.metric,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Switch(
              value: option.enabled,
              onChanged: (_) => bloc.add(ToggleNotificationOption(option.id)),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red.shade300,
              ),
              tooltip: 'Remove',
              onPressed: () => bloc.add(RemoveNotificationOption(option.id)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddOptionDialog extends StatefulWidget {
  final List<Account> accounts;
  const _AddOptionDialog({required this.accounts});

  @override
  State<_AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<_AddOptionDialog> {
  late String _selectedAccountId;
  late String _selectedMetricId;
  List<Map<String, String>> _buckets = [];
  String? _selectedBucketId;
  bool _loadingBuckets = false;

  Map<ServiceType, NotibarPlugin> get _plugins =>
      context.read<NotibarBloc>().plugins;

  @override
  void initState() {
    super.initState();
    final firstAccount = widget.accounts.first;
    _selectedAccountId = firstAccount.id;
    final metrics = _supportedMetrics(_plugins, firstAccount.serviceType);
    _selectedMetricId = metrics.isNotEmpty ? metrics.first.id : 'unread';
  }

  Future<void> _loadBuckets(Account account) async {
    if (account.serviceType != ServiceType.microsoft) return;
    final planId = account.config['planId'];
    final token = account.apiKey;
    if (planId == null || planId.isEmpty || token == null || token.isEmpty) {
      setState(() {
        _buckets = [];
        _selectedBucketId = null;
      });
      return;
    }

    setState(() => _loadingBuckets = true);
    final buckets = await MicrosoftPlugin.fetchBucketsForPlan(token, planId);
    if (mounted) {
      setState(() {
        _buckets = buckets;
        _selectedBucketId = buckets.isNotEmpty ? buckets.first['id'] : null;
        _loadingBuckets = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plugins = _plugins;
    final selectedAccount = widget.accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
    );
    final availableMetrics = _supportedMetrics(
      plugins,
      selectedAccount.serviceType,
    );

    return AlertDialog(
      title: const Text('Add Notification Item'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedAccountId,
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cloud_outlined),
              ),
              items: widget.accounts.map((a) {
                return DropdownMenuItem(
                  value: a.id,
                  child: Row(
                    children: [
                      Icon(_serviceIcon(plugins, a.serviceType), size: 18),
                      const SizedBox(width: 8),
                      Text(a.name),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedAccountId = v;
                    final newAccount = widget.accounts.firstWhere(
                      (a) => a.id == v,
                    );
                    final newMetrics = _supportedMetrics(
                      plugins,
                      newAccount.serviceType,
                    );
                    if (!newMetrics.any((m) => m.id == _selectedMetricId)) {
                      _selectedMetricId = newMetrics.isNotEmpty
                          ? newMetrics.first.id
                          : 'unread';
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedMetricId,
              decoration: const InputDecoration(
                labelText: 'What to show',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.visibility_outlined),
              ),
              items: availableMetrics.map((m) {
                return DropdownMenuItem(
                  value: m.id,
                  child: Row(
                    children: [
                      Icon(m.materialIcon, size: 18),
                      const SizedBox(width: 8),
                      Text(m.label),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedMetricId = v;
                  });
                  if (v == 'plannerBucket') {
                    final account = widget.accounts.firstWhere(
                      (a) => a.id == _selectedAccountId,
                    );
                    _loadBuckets(account);
                  }
                }
              },
            ),
            if (_selectedMetricId == 'plannerBucket') ...[
              const SizedBox(height: 16),
              if (_loadingBuckets)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_buckets.isEmpty)
                const Text(
                  'No buckets found. Make sure a Planner plan is selected in the account settings.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedBucketId,
                  decoration: const InputDecoration(
                    labelText: 'Bucket',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.view_column_outlined),
                  ),
                  items: _buckets.map((b) {
                    return DropdownMenuItem(
                      value: b['id'],
                      child: Text(b['name'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedBucketId = v);
                    }
                  },
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final account = widget.accounts.firstWhere(
              (a) => a.id == _selectedAccountId,
            );
            final metricDef = availableMetrics
                .where((m) => m.id == _selectedMetricId)
                .firstOrNull;
            var label =
                '${account.name} — ${metricDef?.label ?? _selectedMetricId}';
            var config = <String, String>{};

            // Add bucket config for plannerBucket metric
            if (_selectedMetricId == 'plannerBucket' &&
                _selectedBucketId != null) {
              final bucket = _buckets.firstWhere(
                (b) => b['id'] == _selectedBucketId,
                orElse: () => {},
              );
              config['bucketId'] = _selectedBucketId!;
              config['bucketName'] = bucket['name'] ?? '';
              label = '${account.name} — ${bucket['name'] ?? 'Bucket'}';
            }

            final option = NotificationOption(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              accountId: _selectedAccountId,
              label: label,
              metric: _selectedMetricId,
              config: config,
            );
            context.read<NotibarBloc>().add(AddNotificationOption(option));
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  ACCOUNTS TAB — connection/auth setup
// ════════════════════════════════════════════════════════════════════

class _AccountsTab extends StatelessWidget {
  const _AccountsTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotibarBloc, NotibarState>(
      builder: (context, state) {
        if (state is! NotibarLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Connections to external services.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _showAddAccountDialog(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.accounts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No accounts yet',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: state.accounts.length,
                      itemBuilder: (context, index) {
                        final account = state.accounts[index];
                        final error =
                            state.summariesByAccountId[account.id]?.error;
                        return _AccountCard(account: account, error: error);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<NotibarBloc>(),
        child: const _AddAccountDialog(),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Account account;
  final PluginError? error;

  const _AccountCard({required this.account, this.error});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plugins = context.read<NotibarBloc>().plugins;
    final hasToken = account.apiKey != null && account.apiKey!.isNotEmpty;
    final isConfigured = _isServiceConfigured(account, plugins);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _serviceIcon(plugins, account.serviceType),
                color: colorScheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  _AccountStatusRow(
                    serviceType: account.serviceType,
                    hasToken: hasToken,
                    isConfigured: isConfigured,
                    error: error,
                  ),
                ],
              ),
            ),
            if ((account.serviceType == ServiceType.microsoft ||
                    account.serviceType == ServiceType.teams) &&
                isConfigured)
              _LoginButton(account: account, hasToken: hasToken),
            if (account.serviceType == ServiceType.microsoft && hasToken)
              _PlanPickerButton(account: account),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: 'Configure',
              onPressed: () => _showEditDialog(context),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red.shade300,
              ),
              tooltip: 'Remove',
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
      ),
    );
  }

  bool _isServiceConfigured(
    Account account,
    Map<ServiceType, NotibarPlugin> plugins,
  ) {
    final requiredKeys = _configFields(plugins, account.serviceType).keys;
    return requiredKeys.every(
      (key) => account.config[key] != null && account.config[key]!.isNotEmpty,
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<NotibarBloc>(),
        child: _EditAccountDialog(account: account),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Account'),
        content: Text(
          'Remove "${account.name}" and all its notification items?\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<NotibarBloc>().add(RemoveAccount(account.id));
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _AccountStatusRow extends StatelessWidget {
  final ServiceType serviceType;
  final bool hasToken;
  final bool isConfigured;
  final PluginError? error;

  const _AccountStatusRow({
    required this.serviceType,
    required this.hasToken,
    required this.isConfigured,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final plugins = context.read<NotibarBloc>().plugins;
    final chips = <Widget>[
      _Chip(label: _serviceLabel(plugins, serviceType), color: Colors.blueGrey),
    ];

    if (!isConfigured) {
      chips.add(const _Chip(label: 'Needs setup', color: Colors.orange));
    } else if (!hasToken) {
      chips.add(const _Chip(label: 'Not signed in', color: Colors.orange));
    } else if (error != null) {
      chips.add(const _Chip(label: 'Error', color: Colors.red));
      chips.add(_Chip(label: error!.message, color: Colors.red));
    } else {
      chips.add(const _Chip(label: 'Connected', color: Colors.green));
    }

    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final Account account;
  final bool hasToken;

  const _LoginButton({required this.account, required this.hasToken});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: Icon(
        hasToken ? Icons.check_circle_outline : Icons.login,
        size: 16,
        color: hasToken ? Colors.green : null,
      ),
      label: Text(
        hasToken ? 'Signed in' : 'Sign in',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => _loginMicrosoft(context),
    );
  }

  Future<void> _loginMicrosoft(BuildContext context) async {
    final bloc = context.read<NotibarBloc>();

    final clientId = account.config['clientId'];
    if (clientId == null || clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configure Client ID first')),
      );
      return;
    }

    final label = _serviceLabel(
      context.read<NotibarBloc>().plugins,
      account.serviceType,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening browser for $label login...')),
    );

    final authService = OutlookAuthService(
      clientId: clientId,
      tenantId: account.config['tenantId'] ?? 'common',
    );
    final result = await authService.login();

    if (!context.mounted) return;

    if (result != null) {
      bloc.add(UpdateAccountToken(account.id, result.accessToken));
      // Store refresh token in account config for automatic token renewal
      if (result.refreshToken != null) {
        final updatedConfig = Map<String, String>.from(account.config);
        updatedConfig['refreshToken'] = result.refreshToken!;
        bloc.add(UpdateAccount(account.copyWith(config: updatedConfig)));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully signed in!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login cancelled or failed'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}

// ─── Plan Picker Button ─────────────────────────────────────────

class _PlanPickerButton extends StatelessWidget {
  final Account account;

  const _PlanPickerButton({required this.account});

  @override
  Widget build(BuildContext context) {
    final hasPlan =
        account.config['planId'] != null &&
        account.config['planId']!.isNotEmpty;
    final planName = account.config['planName'] ?? '';

    return TextButton.icon(
      icon: Icon(
        hasPlan ? Icons.check_circle_outline : Icons.assignment_outlined,
        size: 16,
        color: hasPlan ? Colors.green : null,
      ),
      label: Text(
        hasPlan ? planName : 'Select Plan',
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () => _pickPlan(context),
    );
  }

  Future<void> _pickPlan(BuildContext context) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Loading plans...')));

    final plans = await MicrosoftPlugin.fetchAvailablePlans(token);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    if (plans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No Planner plans found. Make sure you have access to Microsoft 365 groups with plans.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Planner Board'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: plans.length,
            itemBuilder: (ctx, i) {
              final plan = plans[i];
              final isSelected = plan['id'] == account.config['planId'];
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.assignment_outlined,
                  color: isSelected ? Colors.green : null,
                ),
                title: Text(plan['title'] ?? ''),
                subtitle: Text(plan['groupName'] ?? ''),
                selected: isSelected,
                onTap: () => Navigator.pop(ctx, plan),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (account.config['planId'] != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, {'id': '', 'title': '', 'groupName': ''}),
              child: const Text('Clear'),
            ),
        ],
      ),
    );

    if (selected == null || !context.mounted) return;

    final updatedConfig = Map<String, String>.from(account.config);
    if (selected['id']!.isEmpty) {
      updatedConfig.remove('planId');
      updatedConfig.remove('planName');
    } else {
      updatedConfig['planId'] = selected['id']!;
      updatedConfig['planName'] = selected['title']!;
    }

    context.read<NotibarBloc>().add(
      UpdateAccount(account.copyWith(config: updatedConfig)),
    );
  }
}

// ─── Add Account Dialog ──────────────────────────────────────────

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  ServiceType _selectedType = ServiceType.microsoft;
  final Map<String, TextEditingController> _configControllers = {};

  Map<ServiceType, NotibarPlugin> get _plugins =>
      context.read<NotibarBloc>().plugins;

  @override
  void initState() {
    super.initState();
    _nameController.text = _serviceLabel(_plugins, _selectedType);
    _rebuildConfigControllers();
  }

  void _rebuildConfigControllers() {
    for (final c in _configControllers.values) {
      c.dispose();
    }
    _configControllers.clear();
    for (final key in _configFields(_plugins, _selectedType).keys) {
      _configControllers[key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    for (final c in _configControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plugins = _plugins;
    final fields = _configFields(plugins, _selectedType);

    return AlertDialog(
      title: const Text('Add Account'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ServiceType>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Service',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
                items: ServiceType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_serviceIcon(plugins, type), size: 18),
                        const SizedBox(width: 8),
                        Text(_serviceLabel(plugins, type)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                      _nameController.text = _serviceLabel(plugins, value);
                      _rebuildConfigControllers();
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              if (_selectedType != ServiceType.microsoft &&
                  _selectedType != ServiceType.teams) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key / Token',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
              ],
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Service Configuration',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...fields.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _configControllers[entry.key],
                      decoration: InputDecoration(
                        labelText: entry.value,
                        border: const OutlineInputBorder(),
                        hintText: _hintForKey(entry.key),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }

  String? _hintForKey(String key) {
    switch (key) {
      case 'clientId':
        return 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
      case 'tenantId':
        return 'common';
      case 'baseUrl':
        return 'https://...';
      case 'frappe':
        return 'api_key:api_secret';
      default:
        return null;
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final config = <String, String>{};
    for (final entry in _configControllers.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) config[entry.key] = v;
    }

    final account = Account(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      serviceType: _selectedType,
      config: config,
      apiKey: _apiKeyController.text.trim().isNotEmpty
          ? _apiKeyController.text.trim()
          : null,
    );
    context.read<NotibarBloc>().add(AddAccount(account));
    Navigator.pop(context);
  }
}

// ─── Edit Account Dialog ──────────────────────────────────────────

class _EditAccountDialog extends StatefulWidget {
  final Account account;
  const _EditAccountDialog({required this.account});

  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  late final Map<String, TextEditingController> _configControllers;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
    _endpointController = TextEditingController(
      text: widget.account.endpoint ?? '',
    );
    _apiKeyController = TextEditingController(
      text: widget.account.apiKey ?? '',
    );
    _configControllers = {};
    final fields = _configFields(
      context.read<NotibarBloc>().plugins,
      widget.account.serviceType,
    );
    for (final key in fields.keys) {
      _configControllers[key] = TextEditingController(
        text: widget.account.config[key] ?? '',
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    for (final c in _configControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plugins = context.read<NotibarBloc>().plugins;
    final fields = _configFields(plugins, widget.account.serviceType);

    return AlertDialog(
      title: Row(
        children: [
          Icon(_serviceIcon(plugins, widget.account.serviceType), size: 22),
          const SizedBox(width: 8),
          Text('Edit ${widget.account.name}'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endpointController,
                decoration: const InputDecoration(
                  labelText: 'Custom Endpoint (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Leave empty for default',
                ),
              ),
              if (widget.account.serviceType != ServiceType.microsoft &&
                  widget.account.serviceType != ServiceType.teams) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key / Token',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
              ],
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Service Configuration',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...fields.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _configControllers[entry.key],
                      decoration: InputDecoration(
                        labelText: entry.value,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final config = <String, String>{};
    for (final entry in _configControllers.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) config[entry.key] = v;
    }

    final endpoint = _endpointController.text.trim();

    final updated = widget.account.copyWith(
      name: name,
      endpoint: endpoint.isNotEmpty ? endpoint : null,
      apiKey: _apiKeyController.text.trim().isNotEmpty
          ? _apiKeyController.text.trim()
          : null,
      config: config,
    );

    context.read<NotibarBloc>().add(UpdateAccount(updated));
    Navigator.pop(context);
  }
}
