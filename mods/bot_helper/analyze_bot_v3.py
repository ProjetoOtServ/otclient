import re

path = r'C:\otclient\mods\bot_helper\bothelper.lua'

def analyze(path):
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    stack = []
    openers = {'function', 'if', 'for', 'while', 'do'}
    
    for i, line in enumerate(lines, 1):
        # Very simple: ignore comments and strings
        clean = line.split('--')[0]
        # Ignore strings by replacing them with something safe
        clean = re.sub(r'\'[^\']*\'', 'STR', clean)
        clean = re.sub(r'"[^"]*"', 'STR', clean)
        
        # Now find keywords
        tokens = re.findall(r'\b(function|if|for|while|do|then|end)\b', clean)
        
        for t in tokens:
            if t in openers:
                stack.append((t, i))
            elif t == 'end':
                if stack:
                    stack.pop()
                else:
                    print(f"Error: Extra 'end' at line {i}")
                    
    if not stack:
        print("Success: File is perfectly balanced!")
    else:
        print(f"Failure: {len(stack)} open blocks at EOF")
        for t, l in stack:
            print(f" - [{l}] {t}")

analyze(path)
