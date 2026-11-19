import {Video} from '@remotion/media';
import React from 'react';
import {
  AbsoluteFill,
  Composition,
  Img,
  Sequence,
  Still,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const fps = 30;
const coverSeconds = 3;
const coverFrames = coverSeconds * fps;
const placeholderDemoFrames = 26 * fps;

const palette = {background: '#080a0c', white: '#f4f6f3', muted: '#a0aaa7', accent: '#c7f36b'};

const chapters = [
  {start: 0 / 26, end: 5 / 26, title: 'Notch 展开，开始编辑', detail: 'Ghostty 中运行 cue --wait，唤起 Cue'},
  {start: 5 / 26, end: 9 / 26, title: '查看终端历史上下文', detail: '在 Ghostty 中回看 Pi 对话'},
  {start: 9 / 26, end: 12 / 26, title: '切换到第二桌面', detail: 'Control-G 唤起 Cue，Pi 留在桌面一'},
  {start: 12 / 26, end: 20 / 26, title: '在 Cue 编辑 Prompt', detail: 'Control-G 打开 Pi 外部编辑器'},
  {start: 20 / 26, end: 24 / 26, title: '提交并回到桌面一', detail: '⌘ Return，焦点回到 Ghostty'},
  {start: 24 / 26, end: 1, title: 'Prompt 返回 Pi', detail: '编辑完成，继续当前会话'},
] as const;

const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames: totalFrames} = useVideoConfig();
  const drift = interpolate(frame, [0, totalFrames], [-45, 45], {extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{backgroundColor: palette.background, overflow: 'hidden'}}>
      <div style={{position: 'absolute', width: 1050, height: 1050, right: -320 + drift, top: -560, borderRadius: '50%', background: 'radial-gradient(circle, rgba(199,243,107,0.12) 0%, rgba(199,243,107,0.035) 35%, rgba(8,10,12,0) 72%)'}} />
      <div style={{position: 'absolute', inset: 0, opacity: 0.2, backgroundImage: 'linear-gradient(rgba(255,255,255,0.028) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.028) 1px, transparent 1px)', backgroundSize: '96px 96px', maskImage: 'linear-gradient(to bottom, black, transparent 80%)'}} />
    </AbsoluteFill>
  );
};

const RecordingSlate: React.FC = () => (
  <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', color: palette.white, backgroundColor: '#111416', fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'}}>
    <div style={{fontSize: 38, fontWeight: 600}}>真实 Ghostty / macOS 录屏待采集</div>
    <div style={{fontSize: 21, color: palette.muted, marginTop: 18}}>录屏素材就绪后将全屏呈现，不合成应用界面</div>
  </AbsoluteFill>
);

type DemoProps = {
  readonly recorded: boolean;
  readonly recordingFile: string;
  readonly recordingDurationFrames: number;
  readonly trimBeforeFrames: number;
};

const ProductRecording: React.FC<DemoProps> = ({recorded, recordingFile, recordingDurationFrames, trimBeforeFrames}) => {
  const {fps: compositionFps} = useVideoConfig();
  if (!recorded) return <RecordingSlate />;
  return (
    <Sequence durationInFrames={recordingDurationFrames}>
      <Video src={staticFile(recordingFile)} trimBefore={trimBeforeFrames} durationInFrames={recordingDurationFrames} objectFit="contain" muted premountFor={compositionFps} style={{width: '100%', height: '100%'}} />
    </Sequence>
  );
};

const BrandMark: React.FC<{size?: number}> = ({size = 42}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 14}}>
    <Img src={staticFile('cue-logo.svg')} style={{width: size, height: size, filter: 'brightness(0) invert(1)'}} />
    <span style={{fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif', fontSize: size * 0.56, fontWeight: 650, letterSpacing: 4.5, color: palette.white}}>CUE</span>
  </div>
);

const ChapterOverlay: React.FC<{title: string; detail: string; duration: number}> = ({title, detail, duration}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 12, duration - 12, duration], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const y = interpolate(frame, [0, 16], [14, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{justifyContent: 'flex-end', padding: '0 112px 92px', pointerEvents: 'none'}}>
      <div style={{opacity, translate: `0px ${y}px`, fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif', textShadow: '0 2px 22px rgba(0,0,0,0.9)'}}>
        <div style={{color: palette.white, fontWeight: 650, fontSize: 44, letterSpacing: -1.2}}>{title}</div>
        <div style={{color: '#e2e7e2', fontSize: 23, marginTop: 10, letterSpacing: 0.1}}>{detail}</div>
      </div>
    </AbsoluteFill>
  );
};

export const DemoCut: React.FC<DemoProps> = ({recorded, recordingFile, recordingDurationFrames, trimBeforeFrames}) => {
  const frame = useCurrentFrame();
  const {fps: compositionFps, width} = useVideoConfig();
  const demoFrames = recorded ? recordingDurationFrames : placeholderDemoFrames;
  const coverStart = demoFrames;
  const videoScale = interpolate(frame, [0, demoFrames], [1, 1.018], {extrapolateRight: 'clamp'});
  const coverOpacity = interpolate(frame, [coverStart, coverStart + 0.35 * compositionFps], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const progress = interpolate(frame, [0, demoFrames], [0, width - 224], {extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{backgroundColor: palette.background, overflow: 'hidden'}}>
      <AbsoluteFill style={{scale: videoScale}}><ProductRecording recorded={recorded} recordingFile={recordingFile} recordingDurationFrames={demoFrames} trimBeforeFrames={trimBeforeFrames} /></AbsoluteFill>
      {chapters.map((chapter) => (
        <Sequence key={chapter.title} from={Math.round(chapter.start * demoFrames)} durationInFrames={Math.max(1, Math.round((chapter.end - chapter.start) * demoFrames))} premountFor={compositionFps}>
          <ChapterOverlay title={chapter.title} detail={chapter.detail} duration={Math.max(1, Math.round((chapter.end - chapter.start) * demoFrames))} />
        </Sequence>
      ))}
      <div style={{position: 'absolute', left: 112, right: 112, bottom: 38, height: 2, background: 'rgba(255,255,255,0.22)'}}>
        <div style={{height: '100%', width: progress, backgroundColor: palette.accent}} />
      </div>
      <Sequence from={coverStart} durationInFrames={coverFrames}>
        <AbsoluteFill style={{opacity: coverOpacity}}><Cover /></AbsoluteFill>
      </Sequence>
    </AbsoluteFill>
  );
};

export const Cover: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: palette.background, overflow: 'hidden'}}>
    <Background />
    <div style={{position: 'absolute', top: 94, left: 156}}><BrandMark size={50} /></div>
    <div style={{position: 'absolute', left: 156, top: 364, color: palette.white, fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'}}>
      <div style={{fontSize: 20, color: palette.accent, letterSpacing: 5, fontWeight: 700, marginBottom: 24}}>PRODUCT DEMO</div>
      <div style={{fontSize: 88, lineHeight: 1.05, fontWeight: 650, letterSpacing: -4}}>Cue Notchpad</div>
      <div style={{fontSize: 31, color: palette.muted, marginTop: 24}}>编辑 prompt，保持思路不断</div>
    </div>
    <div style={{position: 'absolute', right: 160, bottom: 150, width: 300, height: 2, backgroundColor: palette.accent, opacity: 0.9}} />
  </AbsoluteFill>
);

export const CompositionRoot: React.FC = () => (
  <>
    <Composition
      id="DemoCut"
      component={DemoCut}
      width={1920}
      height={1080}
      fps={fps}
      durationInFrames={placeholderDemoFrames + coverFrames}
      defaultProps={{recorded: false, recordingFile: '', recordingDurationFrames: placeholderDemoFrames, trimBeforeFrames: 0}}
      calculateMetadata={({props}) => ({
        durationInFrames: (props.recorded ? props.recordingDurationFrames : placeholderDemoFrames) + coverFrames,
      })}
    />
    <Still id="Cover" component={Cover} width={1920} height={1080} />
  </>
);
