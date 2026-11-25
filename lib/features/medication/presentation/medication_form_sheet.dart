import 'package:flutter/material.dart';

import '../../../models/medication.dart';

class MedicationFormResult {
  const MedicationFormResult({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
    required this.stock,
  });

  final String name;
  final String dosage;
  final String instructions;
  final List<String> times;
  final int? stock;
}

class MedicationFormSheet extends StatefulWidget {
  const MedicationFormSheet({
    super.key,
    this.medication,
    this.errorMessage,
    this.isEditing,
  });

  final Medication? medication;
  final String? errorMessage;
  final bool? isEditing;

  @override
  State<MedicationFormSheet> createState() => _MedicationFormSheetState();
}

class _MedicationFormSheetState extends State<MedicationFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _timesController;
  late final TextEditingController _stockController;

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    _nameController = TextEditingController(text: medication?.name ?? '');
    _dosageController = TextEditingController(text: medication?.dosage ?? '');
    _instructionsController = TextEditingController(
      text: medication?.instructions ?? 'Conforme prescrição',
    );
    _timesController = TextEditingController(
      text: medication?.times.join(', ') ?? '',
    );
    _stockController = TextEditingController(
      text: medication?.stock?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _timesController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  String? _validateTimes(String? value) {
    final times =
        value
            ?.split(',')
            .map((time) => time.trim())
            .where((time) => time.isNotEmpty)
            .toList() ??
        [];
    if (times.isEmpty) return 'Informe ao menos um horário.';
    final validTime = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (times.any((time) => !validTime.hasMatch(time))) {
      return 'Use o formato 08:00, 20:00.';
    }
    if (times.toSet().length != times.length) {
      return 'Remova horários repetidos.';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final stockText = _stockController.text.trim();
    final stock = stockText.isEmpty ? null : int.tryParse(stockText);
    if (stockText.isNotEmpty && stock == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um número inteiro para o estoque.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      MedicationFormResult(
        name: _nameController.text.trim(),
        dosage: _dosageController.text.trim(),
        instructions: _instructionsController.text.trim(),
        times:
            _timesController.text
                .split(',')
                .map((time) => time.trim())
                .where((time) => time.isNotEmpty)
                .toList()
              ..sort(),
        stock: stock,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (widget.isEditing ?? widget.medication != null)
                    ? 'Editar medicamento'
                    : 'Adicionar medicamento',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('medication-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome do medicamento',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome.'
                    : null,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('medication-dosage-field'),
                controller: _dosageController,
                decoration: const InputDecoration(
                  labelText: 'Dosagem',
                  hintText: 'Ex.: conforme prescrição',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe a dosagem.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _instructionsController,
                decoration: const InputDecoration(
                  labelText: 'Como tomar',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('medication-times-field'),
                controller: _timesController,
                decoration: const InputDecoration(
                  labelText: 'Horários',
                  hintText: '08:00, 20:00',
                  helperText: 'Separe os horários por vírgula.',
                  border: OutlineInputBorder(),
                ),
                validator: _validateTimes,
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('medication-stock-field'),
                controller: _stockController,
                decoration: const InputDecoration(
                  labelText: 'Unidades em estoque (opcional)',
                  helperText:
                      'A quantidade diminui quando você confirma uma dose.',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final stock = value?.trim() ?? '';
                  if (stock.isNotEmpty &&
                      (int.tryParse(stock) == null || int.parse(stock) < 0)) {
                    return 'Informe um número inteiro igual ou maior que zero.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-medication-button'),
                  onPressed: _save,
                  child: const Text('Salvar medicamento'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
