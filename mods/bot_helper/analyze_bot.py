import re
import os

path = r'C:\otclient\mods\bot_helper\bothelper.lua'

def analyze_lua(content):
    # Remove strings to avoid counting words inside them
    content = re.sub(r'"--"', 'STR_LITERAL', content) # edge case
    content = re.sub(r'\'[^\']*\'', 'STR_LITERAL', content)
    content = re.sub(r'"[^"]*"', 'STR_LITERAL', content)
    
    # Remove multi-line comments
    content = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL)
    # Remove single-line comments
    content = re.sub(r'--.*', '', content)
    
    tokens = re.findall(r'\b(function|if|for|while|do|then|else|elseif|end)\b', content)
    
    stack = []
    mismatches = []
    
    # Operators that open a block
    openers = {'function', 'if', 'for', 'while', 'do'}
    
    for token in tokens:
        if token in openers:
            stack.append(token)
        elif token == 'end':
            if not stack:
                mismatches.append("Extra 'end' found")
            else:
                stack.pop()
    
    return stack, mismatches

try:
    with open(path, 'rb') as f:
        raw = f.read()
    
    # Sanitize: Remove NULL bytes, fix encoding
    clean = raw.replace(b'\x00', b'').decode('utf-8', 'ignore')
    
    stack, mismatches = analyze_lua(clean)
    
    print(f"Final Stack Height: {len(stack)}")
    print(f"Stack Contents: {stack}")
    print(f"Mismatches: {mismatches}")
    
    # Save a sanitized version to see if it fixes the corruption
    with open(path + '.tmp', 'w', encoding='utf-8') as f:
        f.write(clean)
        
except Exception as e:
    print(f"Error: {e}")
