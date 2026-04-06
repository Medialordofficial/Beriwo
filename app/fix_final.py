import re
with open('lib/screens/login_screen.dart', 'r') as f:
    c = f.read()
# fix const Text where child has dynamic color Colors.grey[400]
c = c.replace('                : const Text(', '                : Text(')
c = c.replace('                    child: const Text(', '                    child: Text(')
with open('lib/screens/login_screen.dart', 'w') as f:
    f.write(c)
