part of '../../features/home/presentation/medication_prototype_app.dart';

extension _PrototypeWidgets on _MedicationPrototypeAppState {
  Widget _page({
    required String title,
    String? subtitle,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final titleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    final header = MediaQuery.textScalerOf(context).scale(1) >= 1.5
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleContent,
              if (trailing != null)
                Align(alignment: Alignment.centerRight, child: trailing),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleContent),
              ?trailing,
            ],
          );

    return CustomScrollView(
      key: PageStorageKey<String>(title),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              header,
              const SizedBox(height: 20),
              ...children,
            ]),
          ),
        ),
      ],
    );
  }

  Widget _demoNotice() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: colorScheme.onSecondaryContainer),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Protótipo demonstrativo: os dados são fictícios e ficam apenas nesta sessão.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLabel(DoseStatus status, Color color) {
    final label = switch (status) {
      DoseStatus.taken => 'Confirmada',
      DoseStatus.missed => 'Atrasada',
      DoseStatus.pending => 'Pendente',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
          fontSize: 16,
        ),
      ),
    );
  }

  Color _statusColor(DoseStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (status) {
      DoseStatus.taken =>
        isDark ? const Color(0xFF80D8B5) : const Color(0xFF176B52),
      DoseStatus.missed =>
        isDark ? const Color(0xFFFF9C8E) : const Color(0xFFB33D2D),
      DoseStatus.pending =>
        isDark ? const Color(0xFFFFD166) : const Color(0xFF7B5710),
    };
  }

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _caregiverNotLinkedCard({
    VoidCallback? onConnect,
    bool loading = false,
    String? error,
  }) {
    return _emptyCard(
      icon: Icons.link_off,
      title: 'Nenhuma pessoa idosa conectada',
      message:
          error ??
          'Use o código de conexão da pessoa assistida. Ele vale por 15 minutos '
              'e só pode ser usado uma vez.',
      actionLabel: onConnect == null ? null : 'Conectar com código',
      onAction: loading ? null : onConnect,
    );
  }

  Widget _sectionTitle(String title) =>
      Text(title, style: Theme.of(context).textTheme.titleMedium);

  Widget _disclaimer() {
    return Text(
      'Este aplicativo é um protótipo de apoio e não substitui a prescrição '
      'nem a orientação de profissionais de saúde.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 16,
        height: 1.4,
      ),
    );
  }

  Future<void> _showAccessibilityOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configurações',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _settingsSwitch(
              key: const Key('dark-mode-switch'),
              title: 'Modo escuro',
              subtitle: 'Reduz o brilho da tela.',
              value: widget.darkMode,
              onChanged: widget.onDarkModeChanged,
            ),
            _settingsSwitch(
              key: const Key('large-text-switch'),
              title: 'Ampliar texto para 200%',
              subtitle: 'Dobra o tamanho do texto; a tela pode exigir rolagem.',
              value: widget.largeText,
              onChanged: (value) {
                Navigator.of(context).pop();
                widget.onLargeTextChanged(value);
              },
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Notificações',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _isCaregiver
                  ? 'Aviso se uma dose não for confirmada em 15 minutos.'
                  : 'Lembretes na hora de cada medicamento.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('enable-notifications-button'),
                onPressed: _enableNotifications,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Ativar notificações'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('exact-alarms-button'),
                onPressed: _openExactAlarmSettings,
                icon: const Icon(Icons.alarm),
                label: const Text('Permitir alarmes exatos'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('test-notification-button'),
                onPressed: _sendTestNotification,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Enviar notificação de teste'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsSwitch({
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Switch(key: key, value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
