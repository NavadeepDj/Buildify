"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Menu, X } from "lucide-react";

import { cn } from "@/lib/utils";
import { Logo } from "./logo";
import { GithubIcon } from "./icons";

const links = [
  { href: "/#features", label: "Features" },
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#demo", label: "Demo" },
  { href: "/download", label: "Download" },
  { href: "/#pricing", label: "Pricing" },
  { href: "/docs", label: "Docs" },
  { href: "/#faq", label: "FAQ" },
];

export function SiteNav() {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 w-full transition-all duration-300",
        scrolled
          ? "border-b border-white/5 bg-background/70 backdrop-blur-xl supports-[backdrop-filter]:bg-background/50"
          : "border-b border-transparent"
      )}
    >
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        <Link
          href="/"
          className="flex items-center gap-2 font-semibold tracking-tight"
        >
          <Logo className="h-7 w-7" />
          <span className="text-base">Buildify</span>
          <span className="hidden rounded-md border border-white/10 bg-white/[0.04] px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider text-muted-foreground sm:inline-flex">
            beta
          </span>
        </Link>

        <nav className="hidden items-center gap-1 md:flex">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-white/5 hover:text-foreground"
            >
              {link.label}
            </Link>
          ))}
        </nav>

        <div className="hidden items-center gap-2 md:flex">
          <a
            href="https://github.com/Sujith8257/Buildify"
            target="_blank"
            rel="noreferrer noopener"
            aria-label="GitHub"
            className="inline-flex h-8 items-center gap-1.5 rounded-md px-2.5 text-sm text-muted-foreground transition-colors hover:bg-white/5 hover:text-foreground"
          >
            <GithubIcon className="h-4 w-4" />
            <span className="hidden lg:inline">GitHub</span>
          </a>
          <Link
            href="/download"
            className="inline-flex h-8 items-center gap-1.5 rounded-md bg-foreground px-3 text-sm font-medium text-background transition-colors hover:bg-foreground/90"
          >
            Download
          </Link>
        </div>

        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="inline-flex items-center justify-center rounded-md p-2 text-muted-foreground md:hidden"
          aria-label="Toggle menu"
        >
          {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {open && (
        <div className="border-t border-white/5 bg-background/95 backdrop-blur-xl md:hidden">
          <div className="mx-auto flex max-w-7xl flex-col gap-1 px-4 py-4">
            {links.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                onClick={() => setOpen(false)}
                className="rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-white/5 hover:text-foreground"
              >
                {link.label}
              </Link>
            ))}
            <div className="mt-2 flex gap-2 border-t border-white/5 pt-3">
              <a
                href="https://github.com/Sujith8257/Buildify"
                target="_blank"
                rel="noreferrer noopener"
                className="inline-flex h-9 flex-1 items-center justify-center gap-1.5 rounded-md border border-white/10 bg-white/[0.03] px-3 text-sm font-medium text-foreground"
              >
                <GithubIcon className="h-4 w-4" /> GitHub
              </a>
              <Link
                href="/#waitlist"
                onClick={() => setOpen(false)}
                className="inline-flex h-9 flex-1 items-center justify-center gap-1.5 rounded-md bg-foreground px-3 text-sm font-medium text-background"
              >
                Join waitlist
              </Link>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
