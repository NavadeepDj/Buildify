"use client";

import Link from "next/link";
import { ArrowRight, Sparkles, Download } from "lucide-react";

import { Button } from "@/components/ui/button";
import { GithubIcon } from "@/components/site/icons";
import { AnimatedShinyText } from "@/components/ui/animated-shiny-text";
import { AuroraText } from "@/components/ui/aurora-text";
import { BorderBeam } from "@/components/ui/border-beam";
import { Particles } from "@/components/ui/particles";
import { ShimmerButton } from "@/components/ui/shimmer-button";
import { TextAnimate } from "@/components/ui/text-animate";
import { NumberTicker } from "@/components/ui/number-ticker";
import { cn } from "@/lib/utils";

export function Hero() {
  return (
    <section className="relative isolate overflow-hidden pb-24 pt-24 sm:pt-32">
      <Particles
        className="absolute inset-0 -z-10"
        quantity={90}
        ease={70}
        color="#9adfff"
        refresh={false}
      />
      <div
        aria-hidden
        className="absolute inset-x-0 -top-40 -z-10 transform-gpu overflow-hidden blur-3xl"
      >
        <div
          className="relative left-1/2 aspect-[1155/678] w-[60rem] -translate-x-1/2 bg-gradient-to-tr from-[oklch(0.82_0.16_195)] to-[oklch(0.7_0.2_290)] opacity-20"
          style={{
            clipPath:
              "polygon(74.1% 44.1%, 100% 61.6%, 97.5% 26.9%, 85.5% 0.1%, 80.7% 2%, 72.5% 32.5%, 60.2% 62.4%, 52.4% 68.1%, 47.5% 58.3%, 45.2% 34.5%, 27.5% 76.7%, 0.1% 64.9%, 17.9% 100%, 27.6% 76.8%, 76.1% 97.7%, 74.1% 44.1%)",
          }}
        />
      </div>

      <div className="mx-auto flex max-w-7xl flex-col items-center px-4 text-center sm:px-6 lg:px-8">
        <Link
          href="https://github.com/Sujith8257/Buildify"
          target="_blank"
          rel="noreferrer noopener"
          className="group mb-6 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-4 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-white/5"
        >
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[oklch(0.82_0.16_195)] opacity-60" />
            <span className="relative inline-flex h-2 w-2 rounded-full bg-[oklch(0.82_0.16_195)]" />
          </span>
          <AnimatedShinyText
            className={cn(
              "inline-flex items-center text-sm",
              "text-muted-foreground hover:text-foreground"
            )}
          >
            <span>Open Core · Free forever · Pro from $5/mo</span>
            <ArrowRight className="ml-1 size-3 transition-transform duration-300 ease-in-out group-hover:translate-x-0.5" />
          </AnimatedShinyText>
        </Link>

        <h1 className="text-balance text-5xl font-bold tracking-tight sm:text-7xl">
          <span className="block text-gradient">Host anything.</span>
          <span className="block">
            From your <AuroraText>pocket</AuroraText>.
          </span>
        </h1>

        <TextAnimate
          as="p"
          animation="blurInUp"
          by="word"
          delay={0.2}
          className="mt-6 max-w-2xl text-balance text-lg leading-relaxed text-muted-foreground sm:text-xl"
        >
          Run LLMs and backends locally on Android. Get an OpenAI-compatible
          API on your Wi-Fi — or a public URL at yourname.buildify.me.
          Your hardware, your rules, zero cloud bill.
        </TextAnimate>

        <div className="mt-10 flex flex-col items-center gap-3 sm:flex-row">
          <Link href="/download">
            <ShimmerButton
              className="shadow-2xl"
              shimmerColor="#9adfff"
              background="oklch(0.11 0.015 260)"
            >
              <span className="flex items-center gap-2 whitespace-pre-wrap text-center text-sm font-medium leading-none tracking-tight text-foreground lg:text-base">
                Get Started Free
                <Sparkles className="h-4 w-4" />
              </span>
            </ShimmerButton>
          </Link>
          <a
            href="https://github.com/Sujith8257/Buildify"
            target="_blank"
            rel="noreferrer noopener"
            className="group inline-flex h-11 items-center gap-2 rounded-lg border border-white/10 bg-white/[0.03] px-4 text-sm font-medium text-foreground transition-colors hover:bg-white/[0.06]"
          >
            <GithubIcon className="h-4 w-4" />
            Star on GitHub
            <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
          </a>
        </div>

        <div className="mt-16 grid w-full max-w-3xl grid-cols-3 gap-4">
          <Stat label="Models supported" value={6} suffix="+" />
          <Stat label="Lines of code" value={3500} suffix="+" />
          <Stat label="Cloud spend" value={0} prefix="$" />
        </div>

        <div className="relative mx-auto mt-16 w-full max-w-5xl">
          <div className="absolute inset-0 -z-10 mx-auto h-full max-w-3xl bg-gradient-to-r from-[oklch(0.82_0.16_195)] via-[oklch(0.7_0.2_290)] to-[oklch(0.85_0.18_145)] opacity-25 blur-3xl" />
          <div className="relative overflow-hidden rounded-2xl border border-white/10 bg-card/60 p-1 shadow-2xl backdrop-blur-xl">
            <HeroPreview />
            <BorderBeam
              size={250}
              duration={12}
              colorFrom="oklch(0.82 0.16 195)"
              colorTo="oklch(0.7 0.2 290)"
            />
          </div>
        </div>
      </div>
    </section>
  );
}

function Stat({
  label,
  value,
  prefix,
  suffix,
}: {
  label: string;
  value: number;
  prefix?: string;
  suffix?: string;
}) {
  return (
    <div className="rounded-xl border border-white/5 bg-white/[0.02] p-4 backdrop-blur-sm">
      <div className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
        {prefix}
        <NumberTicker value={value} className="text-foreground" />
        {suffix}
      </div>
      <div className="mt-1 text-xs uppercase tracking-wider text-muted-foreground">
        {label}
      </div>
    </div>
  );
}

function HeroPreview() {
  return (
    <div className="grid grid-cols-1 gap-0 overflow-hidden rounded-xl bg-[oklch(0.05_0.01_260)] md:grid-cols-2">
      <div className="border-b border-white/5 p-6 md:border-b-0 md:border-r">
        <div className="mb-3 flex items-center gap-2 text-xs uppercase tracking-wider text-muted-foreground">
          <span className="inline-flex h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
          On the phone
        </div>
        <div className="space-y-2 font-mono text-xs leading-relaxed text-muted-foreground/90">
          <div>
            <span className="text-emerald-400">●</span>{" "}
            <span className="text-foreground">Server running</span>{" "}
            <span className="text-muted-foreground">on</span>{" "}
            <span className="text-[oklch(0.82_0.16_195)]">
              navadeep.buildify.me
            </span>
          </div>
          <div className="text-muted-foreground/80">
            <span className="text-[oklch(0.85_0.18_145)]">[system]</span>{" "}
            tinyllama-1.1b-chat-v1.0.Q4.gguf loaded
          </div>
          <div className="text-muted-foreground/80">
            <span className="text-[oklch(0.85_0.18_145)]">[tunnel]</span>{" "}
            <span className="text-[oklch(0.82_0.16_195)]">PRO</span> persistent
            subdomain active
          </div>
          <div className="text-muted-foreground/80">
            <span className="text-[oklch(0.82_0.16_195)]">[request]</span> POST
            /v1/chat/completions 200{" "}
            <span className="text-muted-foreground/60">· 84 tok</span>
          </div>
          <div className="text-muted-foreground/80">
            <span className="text-[oklch(0.82_0.16_195)]">[request]</span> POST
            /v1/chat/completions 200{" "}
            <span className="text-muted-foreground/60">· 64 tok</span>
          </div>
        </div>
      </div>
      <div className="p-6">
        <div className="mb-3 flex items-center gap-2 text-xs uppercase tracking-wider text-muted-foreground">
          <span className="inline-flex h-1.5 w-1.5 rounded-full bg-[oklch(0.7_0.2_290)]" />
          From anywhere
        </div>
        <pre className="overflow-x-auto rounded-lg border border-white/10 bg-black/40 p-3 font-mono text-[11px] leading-relaxed">
          <code className="text-muted-foreground/90">
            <span className="text-[oklch(0.7_0.2_290)]">curl</span>{" "}
            https://navadeep.buildify.me/v1/chat/completions \{"\n"}
            {"  "}-H{" "}
            <span className="text-[oklch(0.85_0.18_145)]">
              &quot;Authorization: Bearer bk_…&quot;
            </span>{" "}
            \{"\n"}
            {"  "}-d{" "}
            <span className="text-[oklch(0.85_0.18_145)]">
              &apos;
              {`{"messages":[{"role":"user","content":"hi"}]}`}
              &apos;
            </span>
          </code>
        </pre>
        <div className="mt-3 rounded-lg border border-white/10 bg-black/40 p-3 text-[11px] leading-relaxed">
          <span className="font-mono text-[oklch(0.82_0.16_195)]">
            assistant
          </span>
          <span className="text-muted-foreground"> →</span>{" "}
          <span className="text-foreground/90">
            Beneath the lush canopy of the Amazon, a small tribe lives in
            harmony with the environment…
          </span>
        </div>
      </div>
    </div>
  );
}
