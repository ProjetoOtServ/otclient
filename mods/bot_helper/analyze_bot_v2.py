import re
import os

path = r'C:\otclient\mods\bot_helper\bothelper.lua'

def analyze_lua(content):
    # Strip comments first to avoid false openers
    content = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL)
    
    # Track openers by line number
    lines = content.splitlines()
    stack = []
    
    # Operators that open a block
    openers = {'function', 'if', 'for', 'while', 'do'}
    
    for i, line in enumerate(lines, 1):
        # Strip strings and single-line comments from this line for analysis
        line_clean = re.sub(r'--.*', '', line)
        line_clean = re.sub(r'\'[^\']*\'', 'STR_LITERAL', line_clean)
        line_clean = re.sub(r'"[^"]*"', 'STR_LITERAL', line_clean)
        
        # Tokenize carefully
        tokens = re.findall(r'\b(function|if|for|while|do|then|end)\b', line_clean)
        
        for token in tokens:
            if token in openers:
                # Basic on-line closer check: if cond then ... end
                if token == 'if' and 'end' in tokens and tokens.index('end') > tokens.index('if'):
                    # Probable single line if, but only if it's really the right 'end'
                    # Actually, just use a stack; it's safer.
                    pass 
                
                stack.append((token, i))
            elif token == 'end':
                if stack:
                    stack.pop()
                else:
                    print(f"ERROR: Extra 'end' at line {i}")
    
    return stack

try:
    with open(path, 'rb') as f: raw = f.read()
    clean = raw.replace(b'\x00', b'').decode('utf-8', 'ignore')
    
    open_stack = analyze_lua(clean)
    
    if not open_stack:
        print("Success: File is perfectly balanced!")
    else:
        print(f"Failure: {len(open_stack)} open blocks at EOF.")
        for token, line_no in open_stack:
            print(f" - [{line_no}] {token}")
            
except Exception as e:
    print(f"Error: {e}")
