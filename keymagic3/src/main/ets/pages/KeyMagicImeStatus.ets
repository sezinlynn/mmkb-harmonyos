/**
 * Compact, non-interactive composition bubble for IME-owned composition in
 * every editor. It observes IME-owned composition and cannot receive focus.
 */
@Entry
@Component
struct KeyMagicImeStatus {
  @StorageLink('keymagicImeCompositionPopupVisible') popupVisible: string = 'false';
  @StorageLink('keymagicImeCompositionPopupText') composition: string = '';
  @StorageLink('keymagicImeCompositionPopupColorMode') colorMode: string = 'light';

  private isDarkMode(): boolean {
    return this.colorMode === 'dark';
  }

  build() {
    Column() {
      if (this.popupVisible === 'true' && this.composition.length > 0) {
        // A normal composition must be one unconstrained Text layout. In
        // particular, do not place it in a Scroll viewport that can hide the
        // newest tail before the native panel catches up with the new height.
        Text(this.composition)
        .width('100%')
        .fontSize('17fp')
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode() ?
          $r('app.color.keymagic_composition_popup_foreground_dark') :
          $r('app.color.keymagic_composition_popup_foreground_light'))
        // Keep the compact 17fp glyphs inside a fixed Myanmar-safe line
        // box, including upper and lower combining marks from first draw.
        .lineHeight('33vp')
        .wordBreak(WordBreak.BREAK_WORD)
        .lineBreakStrategy(LineBreakStrategy.GREEDY)
        .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: '10vp', right: '10vp', top: '6vp', bottom: '6vp' })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode() ?
      $r('app.color.keymagic_composition_popup_background_dark') :
      $r('app.color.keymagic_composition_popup_background_light'))
    // There is no public IME API for the focused editor's resolved surface
    // color. Use ArkUI's native material so the surrounding window can still
    // visually influence this compact, non-interactive panel.
    .backgroundBlurStyle(BlurStyle.Regular)
    .border({
      width: 1,
      color: this.isDarkMode() ?
        $r('app.color.keymagic_composition_popup_border_dark') :
        $r('app.color.keymagic_composition_popup_border_light'),
    })
    .shadow({
      radius: 12,
      offsetY: 3,
      color: this.isDarkMode() ?
        $r('app.color.keymagic_composition_popup_shadow_dark') :
        $r('app.color.keymagic_composition_popup_shadow_light'),
    })
    .borderRadius(10)
  }
}
