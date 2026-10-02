/*
 * Задача 5.3 (Objective-C): конвертер Markdown -> HTML.
 *
 * Читает .md файл и генерирует HTML-документ. Поддерживается:
 *   # .. ######        -> <h1> .. <h6>
 *   **жирный**         -> <b>        *курсив* -> <i>        `код` -> <code>
 *   [текст](url)       -> <a href>
 *   пустая строка      -> граница абзаца <p>
 *   - / * / + пункт    -> <ul><li>   1. пункт -> <ol><li>
 *   > цитата           -> <blockquote>
 *   ``` блок кода ```  -> <pre><code>
 *   ---                -> <hr>
 * Спецсимволы & < > экранируются.
 *
 * Сборка (GNUstep):
 *   gcc $(gnustep-config --objc-flags) md2html.m -o md2html $(gnustep-config --base-libs)
 * Запуск: ./md2html <вход.md> [выход.html]
 *
 * Код без ARC и без литералов @[] @{} — так он собирается и gcc, и clang.
 */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface MarkdownConverter : NSObject
{
    NSMutableString *html;       /* результат */
    NSMutableArray *paragraph;   /* строки текущего абзаца */
    NSString *listTag;           /* открытый список: @"ul", @"ol" или nil */
    BOOL inCode;                 /* внутри блока ``` */
    NSString *title;             /* текст первого заголовка h1 */
    int headers, paragraphs, items, codeBlocks;
}
- (NSString *)convert:(NSString *)markdown;
- (NSString *)title;
- (void)printStats;
@end

@implementation MarkdownConverter

- (id)init
{
    if ((self = [super init]) != nil) {
        paragraph = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [paragraph release];
    [html release];
    [title release];
    [super dealloc];
}

- (NSString *)title
{
    return title != nil ? title : @"Document";
}

/* --- Экранирование спецсимволов HTML ---------------------------------- */
static NSString *escapeHTML(NSString *s)
{
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return s;
}

/* Есть ли дальше закрывающий маркер — чтобы одиночная '*' (2 * 3) не открывала курсив */
static BOOL hasCloser(NSString *s, NSUInteger from, NSString *marker)
{
    if (from >= [s length]) return NO;
    NSRange r = [s rangeOfString:marker options:0 range:NSMakeRange(from, [s length] - from)];
    return r.location != NSNotFound;
}

/* --- Строчная разметка: **, *, `, [текст](url) -------------------------- */
- (NSString *)inlineMarkup:(NSString *)raw
{
    NSString *s = escapeHTML(raw);
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0, n = [s length];
    BOOL bold = NO, italic = NO, code = NO;

    while (i < n) {
        unichar c = [s characterAtIndex:i];

        if (c == '`' && (code || hasCloser(s, i + 1, @"`"))) {
            [out appendString:(code ? @"</code>" : @"<code>")];
            code = !code;
            i++;
            continue;
        }
        if (code) {                       /* внутри `кода` разметку не трогаем */
            [out appendFormat:@"%C", c];
            i++;
            continue;
        }
        if (c == '*' && i + 1 < n && [s characterAtIndex:i + 1] == '*'
            && (bold || hasCloser(s, i + 2, @"**"))) {
            [out appendString:(bold ? @"</b>" : @"<b>")];
            bold = !bold;
            i += 2;
            continue;
        }
        if (c == '*' && (italic || hasCloser(s, i + 1, @"*"))) {
            [out appendString:(italic ? @"</i>" : @"<i>")];
            italic = !italic;
            i++;
            continue;
        }
        if (c == '[') {                   /* ссылка [текст](url) */
            NSRange mid = [s rangeOfString:@"](" options:0 range:NSMakeRange(i, n - i)];
            if (mid.location != NSNotFound) {
                NSUInteger urlStart = mid.location + 2;
                NSRange close = [s rangeOfString:@")" options:0
                                           range:NSMakeRange(urlStart, n - urlStart)];
                if (close.location != NSNotFound) {
                    NSString *text = [s substringWithRange:NSMakeRange(i + 1, mid.location - i - 1)];
                    NSString *url = [s substringWithRange:NSMakeRange(urlStart, close.location - urlStart)];
                    url = [url stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
                    [out appendFormat:@"<a href=\"%@\">%@</a>", url, text];
                    i = close.location + 1;
                    continue;
                }
            }
        }
        [out appendFormat:@"%C", c];
        i++;
    }
    /* закрыть то, что осталось открытым, в обратном порядке */
    if (italic) [out appendString:@"</i>"];
    if (bold) [out appendString:@"</b>"];
    if (code) [out appendString:@"</code>"];
    return out;
}

/* --- Блоки ----------------------------------------------------------------- */
- (void)flushParagraph
{
    if ([paragraph count] > 0) {
        NSString *text = [paragraph componentsJoinedByString:@" "];
        [html appendFormat:@"<p>%@</p>\n", [self inlineMarkup:text]];
        [paragraph removeAllObjects];
        paragraphs++;
    }
}

- (void)closeList
{
    if (listTag != nil) {
        [html appendFormat:@"</%@>\n", listTag];
        listTag = nil;
    }
}

- (void)openList:(NSString *)tag
{
    [self flushParagraph];
    if (listTag != nil && ![listTag isEqualToString:tag]) [self closeList];
    if (listTag == nil) {
        [html appendFormat:@"<%@>\n", tag];
        listTag = tag;
    }
}

/* Уровень заголовка: число '#' (1..6), за которыми пробел; 0 — не заголовок */
static int headerLevel(NSString *line)
{
    NSUInteger i = 0, n = [line length];
    while (i < n && i < 7 && [line characterAtIndex:i] == '#') i++;
    if (i >= 1 && i <= 6 && i < n && [line characterAtIndex:i] == ' ') return (int)i;
    return 0;
}

/* Длина префикса нумерованного пункта "12. "; 0 — не пункт */
static NSUInteger orderedPrefix(NSString *line)
{
    NSUInteger i = 0, n = [line length];
    while (i < n && [line characterAtIndex:i] >= '0' && [line characterAtIndex:i] <= '9') i++;
    if (i > 0 && i + 1 < n && [line characterAtIndex:i] == '.' && [line characterAtIndex:i + 1] == ' ')
        return i + 2;
    return 0;
}

- (NSString *)convert:(NSString *)markdown
{
    [html release];
    html = [[NSMutableString alloc] init];
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    NSUInteger k;

    for (k = 0; k < [lines count]; k++) {
        NSString *line = [lines objectAtIndex:k];
        if ([line hasSuffix:@"\r"]) line = [line substringToIndex:[line length] - 1];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:ws];

        /* блок кода: всё дословно, только экранирование */
        if (inCode) {
            if ([trimmed hasPrefix:@"```"]) {
                [html appendString:@"</code></pre>\n"];
                inCode = NO;
            } else {
                [html appendFormat:@"%@\n", escapeHTML(line)];
            }
            continue;
        }
        if ([trimmed hasPrefix:@"```"]) {
            [self flushParagraph];
            [self closeList];
            [html appendString:@"<pre><code>"];
            inCode = YES;
            codeBlocks++;
            continue;
        }

        /* пустая строка — граница абзаца */
        if ([trimmed length] == 0) {
            [self flushParagraph];
            [self closeList];
            continue;
        }

        int level = headerLevel(trimmed);
        if (level > 0) {
            [self flushParagraph];
            [self closeList];
            NSString *text = [[trimmed substringFromIndex:level] stringByTrimmingCharactersInSet:ws];
            [html appendFormat:@"<h%d>%@</h%d>\n", level, [self inlineMarkup:text], level];
            if (level == 1 && title == nil) title = [text retain];
            headers++;
            continue;
        }

        if ([trimmed isEqualToString:@"---"] || [trimmed isEqualToString:@"***"]) {
            [self flushParagraph];
            [self closeList];
            [html appendString:@"<hr>\n"];
            continue;
        }

        if ([trimmed hasPrefix:@"- "] || [trimmed hasPrefix:@"* "] || [trimmed hasPrefix:@"+ "]) {
            [self openList:@"ul"];
            [html appendFormat:@"  <li>%@</li>\n", [self inlineMarkup:[trimmed substringFromIndex:2]]];
            items++;
            continue;
        }

        NSUInteger op = orderedPrefix(trimmed);
        if (op > 0) {
            [self openList:@"ol"];
            [html appendFormat:@"  <li>%@</li>\n", [self inlineMarkup:[trimmed substringFromIndex:op]]];
            items++;
            continue;
        }

        if ([trimmed hasPrefix:@">"]) {
            [self flushParagraph];
            [self closeList];
            NSString *text = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:ws];
            [html appendFormat:@"<blockquote>%@</blockquote>\n", [self inlineMarkup:text]];
            continue;
        }

        /* обычный текст — копим строки абзаца до пустой строки */
        [self closeList];
        [paragraph addObject:trimmed];
    }

    [self flushParagraph];
    [self closeList];
    if (inCode) {
        [html appendString:@"</code></pre>\n"];
        inCode = NO;
    }
    return html;
}

- (void)printStats
{
    fprintf(stderr, "Заголовков: %d, абзацев: %d, пунктов списков: %d, блоков кода: %d\n",
            headers, paragraphs, items, codeBlocks);
}

@end

/* --------------------------------------------------------------------------- */

static NSString *wrapDocument(NSString *body, NSString *title)
{
    return [NSString stringWithFormat:
        @"<!DOCTYPE html>\n"
        @"<html lang=\"ru\">\n<head>\n<meta charset=\"utf-8\">\n<title>%@</title>\n"
        @"<style>\n"
        @"body{max-width:760px;margin:40px auto;padding:0 16px;font-family:sans-serif;line-height:1.6}\n"
        @"code{background:#f2f2f2;padding:2px 4px;border-radius:3px}\n"
        @"pre{background:#f2f2f2;padding:12px;overflow:auto}\n"
        @"pre code{padding:0}\n"
        @"blockquote{margin-left:0;padding-left:12px;border-left:4px solid #ccc;color:#555}\n"
        @"</style>\n</head>\n<body>\n%@</body>\n</html>\n",
        escapeHTML(title), body];
}

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int status = 0;

    if (argc < 2) {
        fprintf(stderr, "Использование: md2html <вход.md> [выход.html]\n");
        [pool drain];
        return 1;
    }

    NSString *inPath = [NSString stringWithUTF8String:argv[1]];
    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfFile:inPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (markdown == nil) {
        fprintf(stderr, "Не удалось прочитать файл %s\n", argv[1]);
        [pool drain];
        return 1;
    }

    MarkdownConverter *converter = [[MarkdownConverter alloc] init];
    NSString *body = [converter convert:markdown];
    NSString *document = wrapDocument(body, [converter title]);

    if (argc >= 3) {
        NSString *outPath = [NSString stringWithUTF8String:argv[2]];
        if ([document writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            printf("Готово: %s -> %s\n", argv[1], argv[2]);
        } else {
            fprintf(stderr, "Не удалось записать файл %s\n", argv[2]);
            status = 1;
        }
    } else {
        fputs([document UTF8String], stdout);
    }
    [converter printStats];

    [converter release];
    [pool drain];
    return status;
}
