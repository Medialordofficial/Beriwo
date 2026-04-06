import re

def clean():
    with open('lib/screens/login_screen.dart', 'r') as f:
        content = f.read()

    # The issue is the replace script broke multiline declarations
    content = content.replace('style: TextStyle(color: Colors.grey[400], \n                        color:', 'style: TextStyle(\n                        color:')
    content = content.replace('style: TextStyle(color: Colors.grey[400], \n                      color: _darkBg,', 'style: const TextStyle(\n                      color: _darkBg,')
    content = content.replace('child: const SizedBox(', 'child: SizedBox(')

    with open('lib/screens/login_screen.dart', 'w') as f:
        f.write(content)

clean()
