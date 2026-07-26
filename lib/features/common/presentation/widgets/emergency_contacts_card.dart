import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/models/emergency_contact.dart';
import '../../../../data/repositories/emergency_contact_repository.dart';

class EmergencyContactsCard extends StatelessWidget {
  const EmergencyContactsCard({super.key, required this.userId});

  final String userId;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relationship = TextEditingController();
    try {
      final contact = await showDialog<EmergencyContact>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add emergency contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
              TextField(
                controller: relationship,
                decoration: const InputDecoration(labelText: 'Relationship'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || phone.text.trim().length < 7) {
                  return;
                }
                Navigator.pop(
                  context,
                  EmergencyContact(
                    id: const Uuid().v4(),
                    name: name.text.trim(),
                    phoneNumber: phone.text.trim(),
                    relationship: relationship.text.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (contact != null) {
        await EmergencyContactRepository().save(userId, contact);
      }
    } finally {
      name.dispose();
      phone.dispose();
      relationship.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = EmergencyContactRepository();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Emergency Contacts',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Add emergency contact',
                ),
              ],
            ),
            StreamBuilder<List<EmergencyContact>>(
              stream: repository.watch(userId),
              builder: (context, snapshot) {
                final contacts = snapshot.data ?? const <EmergencyContact>[];
                if (contacts.isEmpty) {
                  return const Text('Add someone you trust for ride safety.');
                }
                return Column(
                  children: contacts
                      .map(
                        (contact) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.contact_phone_outlined),
                          title: Text(contact.name),
                          subtitle: Text(
                            [
                              contact.phoneNumber,
                              contact.relationship,
                            ].where((value) => value.isNotEmpty).join(' · '),
                          ),
                          trailing: IconButton(
                            onPressed: () =>
                                repository.remove(userId, contact.id),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove contact',
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
