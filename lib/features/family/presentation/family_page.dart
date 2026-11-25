part of '../../home/presentation/medication_prototype_app.dart';

extension _FamilyPage on _MedicationPrototypeAppState {
  Widget _caregiverPersonSwitcher() {
    final selected = _linkedPerson;
    if (selected == null || _linkedPeople.length < 2) {
      return const SizedBox.shrink();
    }
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Pessoa acompanhada',
        border: OutlineInputBorder(),
      ),
      child: DropdownButton<String>(
        key: const Key('caregiver-person-selector'),
        value: selected.id,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final person in _linkedPeople)
            DropdownMenuItem(value: person.id, child: Text(person.name)),
        ],
        onChanged: _careLoading
            ? null
            : (id) {
                final person = _linkedPeople
                    .where((candidate) => candidate.id == id)
                    .firstOrNull;
                if (person != null) _selectCaregiverPerson(person);
              },
      ),
    );
  }

  Widget _buildFamilyPage() {
    if (_isCaregiver) {
      return _buildCaregiverAccountPage();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return _page(
      title: 'Acompanhamento familiar',
      subtitle: 'Pessoa de confiança',
      children: [
        const SizedBox(height: 4),
        if (widget.careService == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.person_outline,
                          color: colorScheme.onPrimaryContainer,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _familyName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('$_familyRelationship • $_familyPhone'),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openFamilyForm,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  MergeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Autorizar compartilhamento',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Compartilha o status das doses.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _familySharingEnabled,
                          onChanged: _setFamilySharingEnabled,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          _buildCareLinkCard(),
        const SizedBox(height: 24),
        _sectionTitle('Resumo de adesão'),
        const SizedBox(height: 10),
        _progressCard(_todayRecords),
        const SizedBox(height: 18),
        _sectionTitle('Avisos para a família'),
        const SizedBox(height: 10),
        ..._buildNoticeList(
          'Avisos de doses atrasadas e conexões aparecerão aqui.',
        ),
        if (widget.careService == null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openFamilyForm,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(
              _familyName.isEmpty ? 'Vincular familiar' : 'Alterar familiar',
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('sign-out-button'),
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sair da conta'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Cartão da pessoa assistida: gerar/copiar/cancelar token e desconectar.
  Widget _buildCareLinkCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final person = _linkedPerson;
    final storedToken = _activeToken;
    final token = storedToken != null && !storedToken.isExpired
        ? storedToken
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              person == null ? 'Conecte um cuidador' : 'Cuidador conectado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              person?.name ??
                  'Gere um código e compartilhe apenas com seu cuidador de '
                      'confiança. Ele poderá iniciar a conexão.',
            ),
            if (person != null) Text(person.email),
            if (person == null && token != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                token.formatted,
                key: const Key('care-token-text'),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(letterSpacing: 2, color: colorScheme.primary),
              ),
              Text(
                'Expira às ${_formatClock(token.expiresAt)}. '
                'Vale para uma única conexão. Compartilhe apenas com seu '
                'cuidador de confiança.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('copy-care-token-button'),
                    onPressed: () => _copyToken(token),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('revoke-care-token-button'),
                    onPressed: _tokenBusy ? null : _revokeActiveToken,
                    icon: const Icon(Icons.block),
                    label: const Text('Cancelar código'),
                  ),
                ],
              ),
            ],
            if (_careError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Não foi possível carregar a conexão: $_careError',
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            if (person == null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('generate-care-token-button'),
                  onPressed: (_careLoading || _tokenBusy)
                      ? null
                      : _createCareToken,
                  icon: const Icon(Icons.key),
                  label: Text(
                    token == null
                        ? 'Gerar código de conexão'
                        : 'Gerar novo código',
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('disconnect-care-button'),
                  onPressed: _careLoading ? null : _disconnectCare,
                  icon: Icon(Icons.link_off, color: colorScheme.error),
                  label: Text(
                    'Desconectar cuidador',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNoticeList(String emptyMessage) {
    if (_familyNotifications.isEmpty) {
      return [
        _emptyCard(
          icon: Icons.notifications_none,
          title: 'Nenhum aviso registrado',
          message: emptyMessage,
        ),
      ];
    }
    return [
      for (final notice in _familyNotifications)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(notice.message),
              subtitle: Text(
                notice.demo
                    ? 'Aviso local de demonstração'
                    : _formatNoticeTime(notice.createdAt),
              ),
            ),
          ),
        ),
    ];
  }

  String _formatNoticeTime(DateTime time) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (sameDay) return 'Hoje às ${_formatClock(time)}';
    return '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')} às ${_formatClock(time)}';
  }

  Widget _buildCaregiverAccountPage() {
    final colorScheme = Theme.of(context).colorScheme;
    return _page(
      title: 'Minha conta',
      subtitle: 'Cuidador',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    color: colorScheme.onPrimaryContainer,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.account.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(widget.account.email),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pessoa acompanhada',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _linkedPerson == null
                      ? 'Nenhuma pessoa idosa está conectada.'
                      : '${_linkedPerson!.name}\n${_linkedPerson!.email}',
                ),
                if (_careError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Não foi possível carregar a conexão: $_careError',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
                if (_linkedPerson == null && widget.careService != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('open-care-link-button'),
                      onPressed: _careLoading
                          ? null
                          : _connectCaregiverWithToken,
                      icon: const Icon(Icons.link),
                      label: const Text('Conectar com código'),
                    ),
                  ),
                ],
                if (_linkedPerson != null &&
                    widget.careService != null &&
                    _linkedPeople.length <
                        CareService.maxCaregiverPatients) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('add-care-link-button'),
                      onPressed: _careLoading
                          ? null
                          : _connectCaregiverWithToken,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(
                        'Adicionar pessoa (${_linkedPeople.length}/'
                        '${CareService.maxCaregiverPatients})',
                      ),
                    ),
                  ),
                ],
                if (_linkedPeople.length >= CareService.maxCaregiverPatients)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Limite de ${CareService.maxCaregiverPatients} pessoas '
                      'acompanhadas atingido.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_linkedPerson != null && widget.careService != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('disconnect-care-button'),
                      onPressed: _careLoading ? null : _disconnectCare,
                      icon: Icon(Icons.link_off, color: colorScheme.error),
                      label: Text(
                        'Desconectar pessoa',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_linkedPeople.length > 1) ...[
          const SizedBox(height: 12),
          _caregiverPersonSwitcher(),
        ],
        const SizedBox(height: 24),
        _sectionTitle('Avisos recentes'),
        const SizedBox(height: 10),
        ..._buildNoticeList(
          'Doses confirmadas e atrasadas da pessoa acompanhada aparecerão aqui.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _showAccessibilityOptions,
          icon: const Icon(Icons.tune),
          label: const Text('Configurações'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('sign-out-button'),
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sair da conta'),
        ),
      ],
    );
  }
}
