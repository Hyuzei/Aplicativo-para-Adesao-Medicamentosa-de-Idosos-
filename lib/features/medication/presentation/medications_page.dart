part of '../../home/presentation/medication_prototype_app.dart';

extension _MedicationsPage on _MedicationPrototypeAppState {
  Widget _buildMedicationsPage() {
    return _page(
      title: widget.account.role == AccountRole.caregiver
          ? 'Medicamentos de ${_linkedPerson?.name ?? 'quem você acompanha'}'
          : 'Meus medicamentos',
      subtitle: widget.account.role == AccountRole.caregiver
          ? 'Lista e horários da pessoa idosa'
          : 'Horários e dosagens',
      children: [
        const SizedBox(height: 4),
        if (widget.account.role == AccountRole.caregiver &&
            _linkedPerson == null)
          _caregiverNotLinkedCard(
            onConnect: widget.careService == null
                ? null
                : _connectCaregiverWithToken,
            loading: _careLoading,
            error: _careError,
          )
        else if (_careLoading)
          const Center(child: CircularProgressIndicator())
        else if (_medications.isEmpty)
          _emptyCard(
            icon: Icons.medication_outlined,
            title: widget.account.role == AccountRole.caregiver
                ? 'Nenhum medicamento cadastrado'
                : 'Sua lista está vazia',
            message: widget.account.role == AccountRole.caregiver
                ? 'A pessoa idosa ainda não cadastrou medicamentos.'
                : 'Cadastre os medicamentos conforme a orientação profissional.',
            actionLabel: widget.account.role == AccountRole.caregiver
                ? null
                : 'Cadastrar medicamento',
            onAction: widget.account.role == AccountRole.caregiver
                ? null
                : () => _openMedicationForm(),
          )
        else
          ..._medications.map(
            (medication) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _medicationCard(medication),
            ),
          ),
        const SizedBox(height: 8),
        if (widget.account.role != AccountRole.caregiver &&
            _medications.isNotEmpty) ...[
          FilledButton.icon(
            key: const Key('add-medication-button'),
            onPressed: () => _openMedicationForm(),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar medicamento'),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _medicationCard(Medication medication) {
    final colorScheme = Theme.of(context).colorScheme;
    final todayStatuses = medication.times
        .map((time) => _doseStatuses[_doseKey(medication.id, time)])
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.medication_outlined,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${medication.dosage} • ${medication.instructions}'),
                    ],
                  ),
                ),
                if (widget.account.role == AccountRole.caredFor)
                  PopupMenuButton<String>(
                    tooltip: 'Ações do medicamento',
                    onSelected: (action) {
                      if (action == 'edit') {
                        _openMedicationForm(medication: medication);
                      } else if (action == 'delete') {
                        _confirmDeleteMedication(medication);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_horiz),
                          SizedBox(width: 4),
                          Text('Ações'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...medication.times.map(
                  (time) => Chip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(time),
                  ),
                ),
                if (medication.stock != null)
                  Chip(
                    avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text('Estoque: ${medication.stock}'),
                  ),
              ],
            ),
            if (todayStatuses.any((status) => status == DoseStatus.taken))
              Text(
                'Dose confirmada hoje',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMedication(Medication medication) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir medicamento?'),
        content: Text('Remover ${medication.name} da rotina?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    _removeMedication(medication);
  }
}
