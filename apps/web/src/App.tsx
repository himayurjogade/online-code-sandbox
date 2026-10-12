import { useState } from 'react';
import { CodeEditor } from './components/CodeEditor.js';
import { LanguageSelector } from './components/LanguageSelector.js';
import { RunButton } from './components/RunButton.js';
import { OutputPanel } from './components/OutputPanel.js';
import { ThemeToggle } from './components/ThemeToggle.js';
import { useExecution } from './hooks/useExecution.js';
import { useTheme } from './hooks/useTheme.js';

const LANGUAGES = ['python', 'javascript', 'cpp', 'c', 'java'] as const;
type Language = (typeof LANGUAGES)[number];

const DEFAULT_CODE: Record<Language, string> = {
  python: `# Welcome to Code Sandbox!
# Write your Python code here and click Run.

def greet(name):
    return f"Hello, {name}! 👋"

print(greet("World"))
print("2 + 2 =", 2 + 2)
`,
  javascript: `// Welcome to Code Sandbox!
// Write your JavaScript code here and click Run.

function greet(name) {
    return \`Hello, \${name}! 👋\`;
}

console.log(greet("World"));
console.log("2 + 2 =", 2 + 2);
`,
  cpp: `// Welcome to Code Sandbox!
// Write your C++ code here and click Run.

#include <iostream>
#include <string>

using namespace std;

int main() {
    string name = "World";
    cout << "Hello, " << name << "! 👋" << endl;
    cout << "2 + 2 = " << 2 + 2 << endl;
    return 0;
}
`,
  c: `// Welcome to Code Sandbox!
// Write your C code here and click Run.

#include <stdio.h>

int main() {
    printf("Hello, World! 👋\\n");
    printf("2 + 2 = %d\\n", 2 + 2);
    return 0;
}
`,
  java: `// Welcome to Code Sandbox!
// Write your Java code here and click Run.

public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, World! 👋");
        System.out.println("2 + 2 = " + (2 + 2));
    }
}
`,
};

/**
 * Root application component.
 * Composes all UI components and wires up hooks.
 * No business logic here — just layout and prop passing.
 */
export function App() {
  const [language, setLanguage] = useState<Language>('python');
  const [codeByLang, setCodeByLang] = useState<Record<Language, string>>(DEFAULT_CODE);
  const [vimMode, setVimMode] = useState(false);

  const code = codeByLang[language];

  const setCode = (newCode: string) => {
    setCodeByLang((prev) => ({ ...prev, [language]: newCode }));
  };

  const handleLanguageChange = (newLang: string) => {
    setLanguage(newLang as Language);
  };
  const { execute, cancel, clearOutput, status, output, error, isRunning } = useExecution();
  const { theme, setTheme, isDark } = useTheme();

  const handleRun = () => {
    if (code.trim()) {
      void execute(language, code);
    }
  };

  return (
    <div className="flex h-screen flex-col overflow-hidden">
      {/* Header */}
      <header className="flex shrink-0 items-center justify-between border-b border-(--color-border) bg-(--color-bg-secondary) px-6 py-2 transition-colors duration-200">
        <div className="flex items-center gap-2">
          <svg viewBox="0 0 24 24" fill="currentColor" className="h-7 w-7 text-(--color-accent)">
            <path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z" />
          </svg>
          <h1 className="bg-gradient-to-br from-(--color-accent) to-(--color-accent-hover) bg-clip-text text-lg font-semibold text-transparent">
            Online Code g editor
          </h1>
        </div>
        <ThemeToggle theme={theme} onToggle={setTheme} />
      </header>

      {/* Main content */}
      <main className="grid flex-1 grid-cols-1 overflow-hidden md:grid-cols-2">
        {/* Editor panel */}
        <section className="flex flex-col overflow-hidden border-b border-(--color-border) md:border-r md:border-b-0">
          <div className="flex shrink-0 items-center gap-2 border-b border-(--color-border) bg-(--color-bg-secondary) px-4 py-2 transition-colors duration-200">
            <LanguageSelector
              languages={LANGUAGES}
              selected={language}
              onChange={handleLanguageChange}
              disabled={isRunning}
            />
            <button
              onClick={() => setVimMode((v) => !v)}
              title="Toggle Vim Mode"
              className={`flex cursor-pointer items-center gap-1 rounded-md border px-3 py-1.5 text-sm font-medium transition-colors ${
                vimMode
                  ? 'border-(--color-accent) bg-(--color-accent)/10 text-(--color-accent)'
                  : 'border-(--color-border) bg-(--color-bg-elevated) text-(--color-text-secondary) hover:border-(--color-border-active) hover:text-(--color-text-primary)'
              }`}
            >
              Vim
            </button>
            <div className="ml-auto">
              <RunButton
                onClick={handleRun}
                onCancel={cancel}
                isRunning={isRunning}
                disabled={!code.trim()}
              />
            </div>
          </div>
          <div className="flex-1 overflow-hidden">
            <CodeEditor
              value={code}
              onChange={setCode}
              language={language}
              isDark={isDark}
              vimMode={vimMode}
            />
          </div>
        </section>

        {/* Output panel */}
        <section className="flex flex-col overflow-hidden">
          <OutputPanel status={status} output={output} error={error} onClear={clearOutput} />
        </section>
      </main>
    </div>
  );
}
