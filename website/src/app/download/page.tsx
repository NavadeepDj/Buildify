"use client";

import { useState } from "react";
import Link from "next/link";
import {
  Download,
  Terminal,
  Smartphone,
  Check,
  Copy,
  ExternalLink,
  Sparkles,
  Zap,
  ShieldCheck,
  Wifi,
  Cpu,
  BatteryCharging,
  ArrowRight,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ShimmerButton } from "@/components/ui/shimmer-button";
import { BorderBeam } from "@/components/ui/border-beam";
import { Particles } from "@/components/ui/particles";
import { AuroraText } from "@/components/ui/aurora-text";
import { GithubIcon } from "@/components/site/icons";

export default function DownloadPage() {
  const [copiedPip, setCopiedPip] = useState(false);
  const [copiedNpm, setCopiedNpm] = useState(false);
  const [activeTab, setActiveTab] = useState<"android" | "python" | "typescript">("android");

  const copyToClipboard = (text: string, type: "pip" | "npm") => {
    navigator.clipboard.writeText(text);
    if (type === "pip") {
      setCopiedPip(true);
      setTimeout(() => setCopiedPip(false), 2000);
    } else {
      setCopiedNpm(true);
      setTimeout(() => setCopiedNpm(false), 2000);
    }
  };

  return (
    <div className="relative isolate min-h-screen overflow-hidden pb-24 pt-16">
      <Particles
        className="absolute inset-0 -z-10"
        quantity={60}
        ease={70}
        color="#9adfff"
        refresh={false}
      />

      {/* Background radial glow */}
      <div
        aria-hidden
        className="absolute inset-x-0 -top-40 -z-10 transform-gpu overflow-hidden blur-3xl"
      >
        <div
          className="relative left-1/2 aspect-[1155/678] w-[64rem] -translate-x-1/2 bg-gradient-to-tr from-[oklch(0.82_0.16_195)] to-[oklch(0.7_0.2_290)] opacity-20"
          style={{
            clipPath:
              "polygon(74.1% 44.1%, 100% 61.6%, 97.5% 26.9%, 85.5% 0.1%, 80.7% 2%, 72.5% 32.5%, 60.2% 62.4%, 52.4% 68.1%, 47.5% 58.3%, 45.2% 34.5%, 27.5% 76.7%, 0.1% 64.9%, 17.9% 100%, 27.6% 76.8%, 76.1% 97.7%, 74.1% 44.1%)",
          }}
        />
      </div>

      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="mx-auto max-w-3xl text-center">
          <div className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 py-1.5 text-xs font-medium text-muted-foreground">
            <span className="flex h-2 w-2 rounded-full bg-[oklch(0.82_0.16_195)]" />
            Buildify Release v0.1.0-beta
          </div>

          <h1 className="mt-6 text-balance text-4xl font-bold tracking-tight sm:text-6xl">
            Host on your phone. <br />
            Build with the <AuroraText>SDK</AuroraText>.
          </h1>

          <p className="mt-4 text-balance text-lg leading-relaxed text-muted-foreground">
            Download the official Android server engine to run LLMs and backends locally,
            then connect to it from Python or TypeScript in under three lines of code.
          </p>

          {/* Quick Filter Tabs */}
          <div className="mt-8 flex justify-center gap-2">
            <button
              onClick={() => setActiveTab("android")}
              className={`flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-all ${
                activeTab === "android"
                  ? "border border-white/20 bg-white/10 text-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-white/5 hover:text-foreground"
              }`}
            >
              <Smartphone className="h-4 w-4" />
              Android Server APK
            </button>
            <button
              onClick={() => setActiveTab("python")}
              className={`flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-all ${
                activeTab === "python"
                  ? "border border-white/20 bg-white/10 text-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-white/5 hover:text-foreground"
              }`}
            >
              <Terminal className="h-4 w-4 text-[#3776AB]" />
              Python SDK
            </button>
            <button
              onClick={() => setActiveTab("typescript")}
              className={`flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-all ${
                activeTab === "typescript"
                  ? "border border-white/20 bg-white/10 text-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-white/5 hover:text-foreground"
              }`}
            >
              <Zap className="h-4 w-4 text-[#3178C6]" />
              TypeScript SDK
            </button>
          </div>
        </div>

        {/* Section 1: Android App Download */}
        {(activeTab === "android" || activeTab === undefined) && (
          <div className="relative mx-auto mt-12 max-w-4xl overflow-hidden rounded-2xl border border-white/10 bg-card/60 p-6 shadow-2xl backdrop-blur-xl sm:p-10">
            <BorderBeam size={300} duration={14} colorFrom="oklch(0.82 0.16 195)" colorTo="oklch(0.7 0.2 290)" />

            <div className="grid gap-8 lg:grid-cols-12 lg:items-center">
              <div className="lg:col-span-7">
                <div className="flex items-center gap-3">
                  <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-white/10 bg-white/[0.04]">
                    <Smartphone className="h-6 w-6 text-[oklch(0.82_0.16_195)]" />
                  </div>
                  <div>
                    <h2 className="text-2xl font-bold tracking-tight">Buildify Android Server</h2>
                    <p className="text-xs text-muted-foreground">Version 0.1.0-beta · ARM64-v8a</p>
                  </div>
                </div>

                <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
                  The native host engine that turns your phone into an edge server. Runs GGUF models
                  via compiled llama.cpp ARM64, serves web projects on multi-port sockets, and creates
                  encrypted Cloudflare tunnels with live public HTTPS links.
                </p>

                <div className="mt-6 flex flex-wrap gap-2">
                  <Badge variant="secondary" className="bg-white/5 text-xs text-foreground">
                    <Cpu className="mr-1 h-3 w-3" /> ARM64-v8a NEON
                  </Badge>
                  <Badge variant="secondary" className="bg-white/5 text-xs text-foreground">
                    <Wifi className="mr-1 h-3 w-3" /> LAN mDNS Discovery
                  </Badge>
                  <Badge variant="secondary" className="bg-white/5 text-xs text-foreground">
                    <ShieldCheck className="mr-1 h-3 w-3" /> 100% Offline & Private
                  </Badge>
                </div>

                <div className="mt-8 flex flex-col gap-3 sm:flex-row">
                  <a
                    href="https://github.com/HaRiThA1130/Buildify/releases/latest"
                    target="_blank"
                    rel="noreferrer noopener"
                  >
                    <ShimmerButton className="w-full sm:w-auto" shimmerColor="#9adfff">
                      <span className="flex items-center gap-2 text-sm font-semibold">
                        <Download className="h-4 w-4" />
                        Download APK (ARM64)
                      </span>
                    </ShimmerButton>
                  </a>
                  <a
                    href="https://github.com/HaRiThA1130/Buildify"
                    target="_blank"
                    rel="noreferrer noopener"
                    className="inline-flex h-11 items-center justify-center gap-2 rounded-lg border border-white/10 bg-white/[0.03] px-4 text-sm font-medium text-foreground transition-colors hover:bg-white/[0.06]"
                  >
                    <GithubIcon className="h-4 w-4" />
                    GitHub Releases
                  </a>
                </div>
              </div>

              {/* Requirements & Specs box */}
              <div className="rounded-xl border border-white/10 bg-black/40 p-5 lg:col-span-5">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Hardware & System Specs
                </h3>
                <ul className="mt-3 space-y-2.5 text-xs text-muted-foreground">
                  <li className="flex items-center justify-between border-b border-white/5 pb-2">
                    <span>OS Version</span>
                    <span className="font-mono text-foreground">Android 10+ (API 29+)</span>
                  </li>
                  <li className="flex items-center justify-between border-b border-white/5 pb-2">
                    <span>Recommended RAM</span>
                    <span className="font-mono text-foreground">6 GB – 12 GB+</span>
                  </li>
                  <li className="flex items-center justify-between border-b border-white/5 pb-2">
                    <span>Architecture</span>
                    <span className="font-mono text-foreground">arm64-v8a</span>
                  </li>
                  <li className="flex items-center justify-between border-b border-white/5 pb-2">
                    <span>Storage Free</span>
                    <span className="font-mono text-foreground">4 GB (for models)</span>
                  </li>
                  <li className="flex items-center justify-between">
                    <span>Inference Runtime</span>
                    <span className="font-mono text-foreground">llama.cpp C++ JNI</span>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        )}

        {/* Section 2: Python SDK */}
        {(activeTab === "python" || activeTab === undefined) && (
          <div className="relative mx-auto mt-8 max-w-4xl overflow-hidden rounded-2xl border border-white/10 bg-card/60 p-6 shadow-2xl backdrop-blur-xl sm:p-10">
            <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
              <div>
                <div className="flex items-center gap-2">
                  <span className="rounded-md bg-[#3776AB]/20 px-2 py-0.5 text-xs font-bold text-[#3776AB]">
                    Python 3.9+
                  </span>
                  <h2 className="text-2xl font-bold tracking-tight">buildify-ai for Python</h2>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">
                  Zero-config auto-discovery, sub-10ms token streaming, battery telemetry, and Gemini 2.0 fallback.
                </p>
              </div>

              {/* Install snippet */}
              <div className="flex items-center gap-2 rounded-lg border border-white/10 bg-black/60 px-3.5 py-2 font-mono text-xs">
                <span className="text-muted-foreground">$</span>
                <span className="text-foreground">pip install buildify-ai</span>
                <button
                  onClick={() => copyToClipboard("pip install buildify-ai", "pip")}
                  className="ml-2 rounded p-1 text-muted-foreground transition-colors hover:bg-white/10 hover:text-foreground"
                  aria-label="Copy install command"
                >
                  {copiedPip ? <Check className="h-3.5 w-3.5 text-green-400" /> : <Copy className="h-3.5 w-3.5" />}
                </button>
              </div>
            </div>

            {/* Code Demo */}
            <div className="mt-6 overflow-hidden rounded-xl border border-white/10 bg-black/70">
              <div className="flex items-center justify-between border-b border-white/10 bg-white/[0.03] px-4 py-2 text-xs font-mono text-muted-foreground">
                <span>quickstart.py</span>
                <span>OpenAI Compatible</span>
              </div>
              <pre className="overflow-x-auto p-4 font-mono text-xs leading-relaxed text-neutral-300">
                <code>{`from buildify import Buildify

# 1. Zero-config: Automatically finds your phone on the Wi-Fi!
client = Buildify.discover()
print(f"Connected to phone at: {client.base_url}")

# 2. Check phone battery & server status
stats = client.device.stats()
print(f"Phone Battery: {stats.battery_pct}% (Charging: {stats.is_charging})")

# 3. Stream tokens directly from your phone's local LLM
stream = client.chat.completions.create(
    model="gemma-2b",
    messages=[{"role": "user", "content": "Explain edge computing in 2 lines."}],
    stream=True,
)

for chunk in stream:
    print(chunk.delta_text, end="", flush=True)`}</code>
              </pre>
            </div>

            <div className="mt-6 grid gap-3 sm:grid-cols-3">
              <div className="rounded-lg border border-white/5 bg-white/[0.02] p-3 text-xs">
                <span className="font-semibold text-foreground">Zero-Config Discovery</span>
                <p className="mt-1 text-muted-foreground">
                  Uses UDP broadcast to connect without looking up your phone IP.
                </p>
              </div>
              <div className="rounded-lg border border-white/5 bg-white/[0.02] p-3 text-xs">
                <span className="font-semibold text-foreground">Gemini 2.0 Fallback</span>
                <p className="mt-1 text-muted-foreground">
                  Transparently reroutes to Gemini 2.0 Flash if phone goes offline.
                </p>
              </div>
              <div className="rounded-lg border border-white/5 bg-white/[0.02] p-3 text-xs">
                <span className="font-semibold text-foreground">LangChain Ready</span>
                <p className="mt-1 text-muted-foreground">
                  Drop-in replacement for ChatOpenAI across agent workflows.
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Section 3: TypeScript SDK */}
        {(activeTab === "typescript" || activeTab === undefined) && (
          <div className="relative mx-auto mt-8 max-w-4xl overflow-hidden rounded-2xl border border-white/10 bg-card/60 p-6 shadow-2xl backdrop-blur-xl sm:p-10">
            <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
              <div>
                <div className="flex items-center gap-2">
                  <span className="rounded-md bg-[#3178C6]/20 px-2 py-0.5 text-xs font-bold text-[#3178C6]">
                    TypeScript / Node 18+
                  </span>
                  <h2 className="text-2xl font-bold tracking-tight">buildify-ai for TypeScript</h2>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">
                  Async iterator streaming, Next.js App Router support, and strict OpenAI-compatible typings.
                </p>
              </div>

              {/* Install snippet */}
              <div className="flex items-center gap-2 rounded-lg border border-white/10 bg-black/60 px-3.5 py-2 font-mono text-xs">
                <span className="text-muted-foreground">$</span>
                <span className="text-foreground">npm install buildify-ai</span>
                <button
                  onClick={() => copyToClipboard("npm install buildify-ai", "npm")}
                  className="ml-2 rounded p-1 text-muted-foreground transition-colors hover:bg-white/10 hover:text-foreground"
                  aria-label="Copy install command"
                >
                  {copiedNpm ? <Check className="h-3.5 w-3.5 text-green-400" /> : <Copy className="h-3.5 w-3.5" />}
                </button>
              </div>
            </div>

            {/* Code Demo */}
            <div className="mt-6 overflow-hidden rounded-xl border border-white/10 bg-black/70">
              <div className="flex items-center justify-between border-b border-white/10 bg-white/[0.03] px-4 py-2 text-xs font-mono text-muted-foreground">
                <span>app/api/chat/route.ts (Next.js)</span>
                <span>Streaming Edge AI</span>
              </div>
              <pre className="overflow-x-auto p-4 font-mono text-xs leading-relaxed text-neutral-300">
                <code>{`import { Buildify } from 'buildify-ai';

const client = new Buildify({
  baseUrl: process.env.BUILDIFY_PHONE_URL, // e.g., http://192.168.1.55:8080 or https://*.trycloudflare.com
  geminiApiKey: process.env.GEMINI_API_KEY,
  fallbackModel: 'gemini-2.0-flash',
  fallbackOnOffline: true, // Seamlessly switches to Gemini 2.0 Flash if phone sleeps
});

export async function POST(req: Request) {
  const { messages } = await req.json();

  const stream = await client.chat.completions.create({
    messages,
    stream: true,
  });

  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      for await (const chunk of stream) {
        controller.enqueue(encoder.encode(chunk.choices[0]?.delta?.content || ''));
      }
      controller.close();
    },
  });

  return new Response(readable, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}`}</code>
              </pre>
            </div>
          </div>
        )}

        {/* Bottom CTA / Help */}
        <div className="mx-auto mt-16 max-w-3xl text-center">
          <p className="text-sm text-muted-foreground">
            Want to see all SDK source files, tests, and documentation?
          </p>
          <div className="mt-4 flex justify-center gap-3">
            <Link
              href="/docs"
              className="inline-flex items-center gap-2 text-sm font-semibold text-[oklch(0.82_0.16_195)] hover:underline"
            >
              Read Architecture Docs
              <ArrowRight className="h-4 w-4" />
            </Link>
            <span className="text-muted-foreground">·</span>
            <a
              href="https://github.com/HaRiThA1130/Buildify"
              target="_blank"
              rel="noreferrer noopener"
              className="inline-flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground"
            >
              <GithubIcon className="h-4 w-4" />
              GitHub Repository
              <ExternalLink className="h-3.5 w-3.5" />
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}
