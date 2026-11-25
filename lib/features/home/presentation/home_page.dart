part of 'medication_prototype_app.dart';

extension _HomePage on _MedicationPrototypeAppState {
  Widget _buildHomePage() {
    if (widget.account.role == AccountRole.caregiver) {
      return _buildCaregiverDashboard();
    }

    final records = _todayRecords;
    final nextRecord = records.cast<DoseRecord?>().firstWhere(
      (record) => record!.status == DoseStatus.pending,
      orElse: () => null,
    );

    return _page(
      title: 'Olá, ${widget.account.name.split(' ').first}',
      subtitle: 'Sua rotina de hoje • Pessoa cuidada',
      trailing: TextButton.icon(
        onPressed: _showAccessibilityOptions,
        icon: const Icon(Icons.tune),
        label: const Text('Configurações'),
      ),
      children: [
        if (widget.careService == null) _demoNotice(),
        const SizedBox(height: 20),
        _sectionTitle('Resumo de hoje'),
        const SizedBox(height: 12),
        _progressCard(records),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            _sectionTitle('Horários do dia'),
            if (records.isNotEmpty)
              TextButton.icon(
                onPressed: () => _openMedicationForm(),
                icon: const Icon(Icons.add, size: 22),
                label: const Text('Adicionar'),
              ),
          ],
        ),
        if (records.isEmpty)
          _emptyCard(
            icon: Icons.medication_outlined,
            title: 'Nenhum medicamento cadastrado',
            message: 'Adicione um medicamento para organizar seus horários.',
            actionLabel: 'Adicionar medicamento',
            onAction: () => _openMedicationForm(),
          )
        else
          ...records.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _doseCard(record),
            ),
          ),
        if (nextRecord != null) ...[
          const SizedBox(height: 8),
          _nextDoseCard(nextRecord),
        ],
        const SizedBox(height: 20),
        _disclaimer(),
      ],
    );
  }

  Widget _buildCaregiverDashboard() {
    final person = _linkedPerson;
    final records = _todayRecords;
    return _page(
      title: 'Olá, ${widget.account.name.split(' ').first}',
      subtitle: 'Painel do cuidador',
      children: [
        if (person == null)
          _caregiverNotLinkedCard(
            onConnect: widget.careService == null
                ? null
                : _connectCaregiverWithToken,
            loading: _careLoading,
            error: _careError,
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Icon(
                      Icons.elderly_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(person.email),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_linkedPeople.length > 1) ...[
            const SizedBox(height: 12),
            _caregiverPersonSwitcher(),
          ],
          const SizedBox(height: 24),
          _sectionTitle('Resumo de hoje'),
          const SizedBox(height: 12),
          _progressCard(records),
          const SizedBox(height: 24),
          _sectionTitle('Doses do dia'),
          const SizedBox(height: 12),
          if (_careLoading)
            const Center(child: CircularProgressIndicator())
          else if (records.isEmpty)
            _emptyCard(
              icon: Icons.medication_outlined,
              title: 'Nenhuma dose cadastrada',
              message: 'As doses aparecerão quando a rotina for cadastrada.',
            )
          else
            ...records.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _caregiverDoseCard(record),
              ),
            ),
          if (_careError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Não foi possível atualizar os dados: $_careError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _selectTab(2),
            icon: const Icon(Icons.history),
            label: const Text('Ver histórico completo'),
          ),
        ],
        const SizedBox(height: 20),
        _disclaimer(),
      ],
    );
  }

  Widget _caregiverDoseCard(DoseRecord record) {
    final color = _statusColor(record.status);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  record.time,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _statusLabel(record.status, color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              record.medication.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${record.medication.dosage} • ${record.medication.instructions}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard(List<DoseRecord> records) {
    final total = records.length;
    final colorScheme = Theme.of(context).colorScheme;
    final taken = records
        .where((record) => record.status == DoseStatus.taken)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.checklist,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$taken de $total doses confirmadas',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text('Doses de hoje'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: total == 0 ? 0 : taken / total,
              minHeight: 10,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: colorScheme.surfaceContainer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _doseCard(DoseRecord record) {
    final statusColor = _statusColor(record.status);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    record.time,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _statusLabel(record.status, statusColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              record.medication.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${record.medication.dosage} • ${record.medication.instructions}',
            ),
            if (record.status == DoseStatus.pending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: Key(
                        'confirm-${record.medication.id}-${record.time}',
                      ),
                      onPressed: () => _updateDose(record, DoseStatus.taken),
                      icon: const Icon(Icons.check),
                      label: const Text('Já tomei'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    key: Key(
                      'dose-actions-${record.medication.id}-${record.time}',
                    ),
                    tooltip: 'Mais opções',
                    onSelected: (action) {
                      if (action == 'snooze') {
                        _snoozeDose(record);
                      } else if (action == 'missed') {
                        _updateDose(record, DoseStatus.missed);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'snooze',
                        child: Text('Lembrar em 10 minutos'),
                      ),
                      PopupMenuItem(
                        value: 'missed',
                        child: Text('Registrar como atrasada'),
                      ),
                    ],
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outline),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_horiz),
                          SizedBox(width: 8),
                          Text('Opções'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nextDoseCard(DoseRecord record) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.alarm, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Próxima dose cadastrada: ${record.time} • ${record.medication.name}',
                style: TextStyle(
                  color: colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
