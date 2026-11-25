part of '../../home/presentation/medication_prototype_app.dart';

extension _HistoryPage on _MedicationPrototypeAppState {
  Widget _buildHistoryPage() {
    if (widget.account.role == AccountRole.caregiver && _linkedPerson == null) {
      return _page(
        title: 'Histórico da pessoa idosa',
        subtitle: 'Conecte-se usando o código da pessoa',
        children: [
          _caregiverNotLinkedCard(
            onConnect: widget.careService == null
                ? null
                : _connectCaregiverWithToken,
            loading: _careLoading,
            error: _careError,
          ),
        ],
      );
    }

    final records = _todayRecords;
    final taken = records
        .where((record) => record.status == DoseStatus.taken)
        .length;
    final missed = records
        .where((record) => record.status == DoseStatus.missed)
        .length;
    final pending = records
        .where((record) => record.status == DoseStatus.pending)
        .length;
    final recorded = taken + missed;
    final adherence = recorded == 0 ? 0 : (taken / recorded * 100).round();
    final colorScheme = Theme.of(context).colorScheme;

    return _page(
      title: widget.account.role == AccountRole.caregiver
          ? 'Histórico de ${_linkedPerson!.name}'
          : 'Histórico e relatórios',
      subtitle: 'Doses de hoje',
      children: [
        if (_careLoading) const LinearProgressIndicator(),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _historyPeriod,
          decoration: const InputDecoration(
            labelText: 'Escolha o período',
            prefixIcon: Icon(Icons.calendar_month),
            border: OutlineInputBorder(),
          ),
          items:
              (widget.careService == null
                      ? const ['Hoje', 'Últimos 7 dias', 'Últimos 30 dias']
                      : const ['Hoje'])
                  .map(
                    (period) =>
                        DropdownMenuItem(value: period, child: Text(period)),
                  )
                  .toList(),
          onChanged: (period) {
            if (period != null) _setHistoryPeriod(period);
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _historyPeriod,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$taken de $recorded doses registradas no prazo',
                  style: const TextStyle(fontSize: 17),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: recorded == 0 ? 0 : taken / recorded,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: colorScheme.surfaceContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  recorded == 0
                      ? 'A adesão será calculada após registrar uma dose.'
                      : 'Índice demonstrativo: $adherence% das doses registradas no prazo.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statChip('No prazo', taken, colorScheme.primaryContainer),
                    _statChip('Atrasadas', missed, colorScheme.errorContainer),
                    _statChip(
                      'Pendentes',
                      pending,
                      colorScheme.tertiaryContainer,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle('Doses registradas'),
        const SizedBox(height: 12),
        if (records.isEmpty)
          _emptyCard(
            icon: Icons.history,
            title: 'Sem registros ainda',
            message: 'As confirmações e atrasos aparecerão aqui.',
          )
        else
          ...records.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _historyRecord(record),
            ),
          ),
        const SizedBox(height: 12),
        if (widget.account.role == AccountRole.caredFor)
          Text(
            'Os períodos de 7 e 30 dias mostram dados desta demonstração.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _historyRecord(DoseRecord record) {
    final icon = switch (record.status) {
      DoseStatus.taken => Icons.check_circle_outline,
      DoseStatus.missed => Icons.error_outline,
      DoseStatus.pending => Icons.schedule,
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: _statusColor(record.status)),
        title: Text(record.medication.name),
        subtitle: Text('${record.time} • ${record.medication.dosage}'),
        trailing: _statusLabel(record.status, _statusColor(record.status)),
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
