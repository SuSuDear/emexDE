from pathlib import Path

app_id_header = Path('TrollStore/Shared/TSUtil.h')
source_file = Path('TrollStore/Shared/TSUtil.m')

header = app_id_header.read_text()
header = header.replace('@"com.opa334.TrollStore"', '@"com.cr4zy.nyxian"')
app_id_header.write_text(header)
if '@"com.cr4zy.nyxian"' not in header:
    raise SystemExit('failed to patch TrollStore APP_ID')

source = source_file.read_text()
old = 'return [trollStorePath() stringByAppendingPathComponent:@"TrollStore.app"];'
new = '''NSString *basePath = trollStorePath();
	NSString *emexDEPath = [basePath stringByAppendingPathComponent:@"emexDE.app"];
	if([[NSFileManager defaultManager] fileExistsAtPath:emexDEPath]) return emexDEPath;
	NSString *emexDEForJBPath = [basePath stringByAppendingPathComponent:@"emexDEForJB.app"];
	if([[NSFileManager defaultManager] fileExistsAtPath:emexDEForJBPath]) return emexDEForJBPath;
	return [basePath stringByAppendingPathComponent:@"TrollStore.app"];'''
source = source.replace(old, new)
source_file.write_text(source)
if 'emexDE.app' not in source:
    raise SystemExit('failed to patch TrollStore app path')
