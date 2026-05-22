import { useCallback, useEffect, useRef, useState } from "react";

type DictationStatus = "idle" | "listening" | "transcribing" | "error";

type SpeechRecognitionAlternativeLike = { transcript: string };
type SpeechRecognitionResultLike = {
  readonly isFinal: boolean;
  readonly length: number;
  item(index: number): SpeechRecognitionAlternativeLike;
  [index: number]: SpeechRecognitionAlternativeLike;
};
type SpeechRecognitionEventLike = {
  readonly resultIndex: number;
  readonly results: {
    readonly length: number;
    item(index: number): SpeechRecognitionResultLike;
    [index: number]: SpeechRecognitionResultLike;
  };
};
type SpeechRecognitionLike = {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onend: (() => void) | null;
  onerror: ((event: { error?: string; message?: string }) => void) | null;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null;
  start: () => void;
  stop: () => void;
  abort: () => void;
};

declare global {
  interface Window {
    SpeechRecognition?: new () => SpeechRecognitionLike;
    webkitSpeechRecognition?: new () => SpeechRecognitionLike;
  }
}

export function useDictation() {
  const [status, setStatus] = useState<DictationStatus>("idle");
  const [liveTranscript, setLiveTranscript] = useState("");
  const [error, setError] = useState<string | null>(null);
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null);
  const finalTextRef = useRef("");
  const latestTextRef = useRef("");
  const activeRef = useRef(false);

  const reset = useCallback(() => {
    activeRef.current = false;
    recognitionRef.current = null;
    finalTextRef.current = "";
    latestTextRef.current = "";
    setLiveTranscript("");
    setStatus("idle");
  }, []);

  const insertLatest = useCallback(() => {
    const text = latestTextRef.current.trim();
    if (!text) return;
    if (!insertIntoFocusedElement(text)) {
      window.dispatchEvent(new CustomEvent("loom-dictation-insert", { detail: { text } }));
    }
  }, []);

  const stop = useCallback(() => {
    if (!activeRef.current) return;
    insertLatest();
    activeRef.current = false;
    setStatus("transcribing");
    recognitionRef.current?.stop();
    reset();
  }, [insertLatest, reset]);

  const cancel = useCallback(() => {
    if (!activeRef.current) return;
    activeRef.current = false;
    recognitionRef.current?.abort();
    reset();
  }, [reset]);

  const start = useCallback(() => {
    if (activeRef.current) return;
    const Recognition = window.SpeechRecognition ?? window.webkitSpeechRecognition;
    if (!Recognition) {
      setStatus("error");
      setError("Dictation is not available in this WebView.");
      return;
    }

    const recognition = new Recognition();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = navigator.language || "en-US";
    recognitionRef.current = recognition;
    finalTextRef.current = "";
    latestTextRef.current = "";
    activeRef.current = true;
    setError(null);
    setLiveTranscript("");
    setStatus("listening");

    recognition.onresult = (event) => {
      let interim = "";
      for (let i = event.resultIndex; i < event.results.length; i += 1) {
        const result = event.results[i] ?? event.results.item(i);
        const transcript = (result[0] ?? result.item(0))?.transcript ?? "";
        if (result.isFinal) finalTextRef.current += transcript + " ";
        else interim += transcript;
      }
      const latest = `${finalTextRef.current}${interim}`.trim();
      latestTextRef.current = latest;
      setLiveTranscript(latest);
    };

    recognition.onerror = (event) => {
      if (!activeRef.current) return;
      activeRef.current = false;
      setStatus("error");
      setError(event.message || event.error || "Dictation failed.");
    };

    recognition.onend = () => {
      if (activeRef.current) reset();
    };

    try {
      recognition.start();
    } catch (err) {
      activeRef.current = false;
      setStatus("error");
      setError(String(err));
    }
  }, [reset]);

  const toggle = useCallback(() => {
    if (activeRef.current) stop();
    else start();
  }, [start, stop]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "F5") {
        event.preventDefault();
        toggle();
      } else if (event.key === "Escape" && activeRef.current) {
        event.preventDefault();
        cancel();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [cancel, toggle]);

  return {
    status,
    isActive: status === "listening" || status === "transcribing",
    liveTranscript,
    error,
    toggle,
  };
}

function insertIntoFocusedElement(text: string): boolean {
  const active = document.activeElement;
  if (active instanceof HTMLTextAreaElement || active instanceof HTMLInputElement) {
    if (active.disabled || active.readOnly) return false;
    const start = active.selectionStart ?? active.value.length;
    const end = active.selectionEnd ?? active.value.length;
    const prefix = active.value.slice(0, start);
    const suffix = active.value.slice(end);
    const spacer = prefix && !prefix.endsWith(" ") ? " " : "";
    const next = `${prefix}${spacer}${text}${suffix}`;
    const proto = active instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
    setter?.call(active, next);
    active.selectionStart = active.selectionEnd = prefix.length + spacer.length + text.length;
    active.dispatchEvent(new Event("input", { bubbles: true }));
    return true;
  }

  if (document.queryCommandSupported?.("insertText")) {
    return document.execCommand("insertText", false, text);
  }
  return false;
}
