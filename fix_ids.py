import os

def replace_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    new_content = content.replace('currentUser.id', 'currentUser.uid')
    new_content = new_content.replace('currentUser?.id', 'currentUser?.uid')
    
    if 'add_status_screen.dart' in filepath:
        new_content = new_content.replace('user.id', 'user.uid')
        
    if new_content != content:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"Fixed {filepath}")

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            replace_in_file(os.path.join(root, file))
