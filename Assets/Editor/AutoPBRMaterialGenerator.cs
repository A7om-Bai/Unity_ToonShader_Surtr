using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

public class AutoPBRMaterialGenerator : EditorWindow
{
    private DefaultAsset targetFolder;
    private bool overwriteExistingMaterial = true;
    private bool overwriteMaterialTextureSlots = true;
    private bool createMaterialInSameFolder = true;

    [MenuItem("Tools/Auto PBR Material Generator")]
    public static void ShowWindow()
    {
        GetWindow<AutoPBRMaterialGenerator>("Auto PBR Generator");
    }

    private void OnGUI()
    {
        GUILayout.Label("Auto PBR Material Generator (URP)", EditorStyles.boldLabel);
        EditorGUILayout.Space();

        targetFolder = (DefaultAsset)EditorGUILayout.ObjectField(
            "Target Folder",
            targetFolder,
            typeof(DefaultAsset),
            false
        );

        overwriteExistingMaterial = EditorGUILayout.Toggle("Overwrite Existing Material", overwriteExistingMaterial);
        overwriteMaterialTextureSlots = EditorGUILayout.Toggle("Overwrite Texture Slots", overwriteMaterialTextureSlots);
        createMaterialInSameFolder = EditorGUILayout.Toggle("Create Material In Same Folder", createMaterialInSameFolder);

        EditorGUILayout.Space();

        if (GUILayout.Button("Scan Folder And Generate Materials", GUILayout.Height(40)))
        {
            if (targetFolder == null)
            {
                EditorUtility.DisplayDialog("Error", "Please assign a target folder.", "OK");
                return;
            }

            string folderPath = AssetDatabase.GetAssetPath(targetFolder);
            if (!AssetDatabase.IsValidFolder(folderPath))
            {
                EditorUtility.DisplayDialog("Error", "Selected object is not a valid folder.", "OK");
                return;
            }

            GenerateMaterials(folderPath);
        }
    }

    private enum TextureType
    {
        Unknown,
        Albedo,
        Normal,
        Metallic,
        Roughness,
        AO,
        Emission
    }

    private class TextureSet
    {
        public string materialKey;
        public string folderPath;
        public string albedoPath;
        public string normalPath;
        public string metallicPath;
        public string roughnessPath;
        public string aoPath;
        public string emissionPath;
    }

    private void GenerateMaterials(string folderPath)
    {
        string[] guids = AssetDatabase.FindAssets("t:Texture2D", new[] { folderPath });
        if (guids == null || guids.Length == 0)
        {
            EditorUtility.DisplayDialog("Info", "No textures found in folder.", "OK");
            return;
        }

        Dictionary<string, TextureSet> groupedSets = new Dictionary<string, TextureSet>();

        try
        {
            AssetDatabase.StartAssetEditing();

            foreach (string guid in guids)
            {
                string assetPath = AssetDatabase.GUIDToAssetPath(guid);
                string fileName = Path.GetFileNameWithoutExtension(assetPath);

                TextureType texType = IdentifyTextureType(fileName);
                if (texType == TextureType.Unknown)
                    continue;

                string key = ExtractMaterialKey(fileName, texType);
                if (string.IsNullOrEmpty(key))
                    continue;

                if (!groupedSets.TryGetValue(key, out TextureSet set))
                {
                    set = new TextureSet
                    {
                        materialKey = key,
                        folderPath = Path.GetDirectoryName(assetPath)?.Replace("\\", "/")
                    };
                    groupedSets.Add(key, set);
                }

                AssignTexturePath(set, texType, assetPath);
                ApplyTextureImportSettings(assetPath, texType);
            }
        }
        finally
        {
            AssetDatabase.StopAssetEditing();
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
        }

        int createdCount = 0;
        int updatedCount = 0;

        foreach (var kv in groupedSets)
        {
            TextureSet set = kv.Value;

            if (string.IsNullOrEmpty(set.albedoPath) &&
                string.IsNullOrEmpty(set.normalPath) &&
                string.IsNullOrEmpty(set.metallicPath) &&
                string.IsNullOrEmpty(set.roughnessPath) &&
                string.IsNullOrEmpty(set.aoPath) &&
                string.IsNullOrEmpty(set.emissionPath))
            {
                continue;
            }

            bool created = CreateOrUpdateMaterial(set);
            if (created) createdCount++;
            else updatedCount++;
        }

        EditorUtility.DisplayDialog(
            "Done",
            $"Finished.\nCreated: {createdCount}\nUpdated: {updatedCount}",
            "OK"
        );
    }

    private void AssignTexturePath(TextureSet set, TextureType texType, string assetPath)
    {
        switch (texType)
        {
            case TextureType.Albedo:
                if (string.IsNullOrEmpty(set.albedoPath)) set.albedoPath = assetPath;
                break;
            case TextureType.Normal:
                if (string.IsNullOrEmpty(set.normalPath)) set.normalPath = assetPath;
                break;
            case TextureType.Metallic:
                if (string.IsNullOrEmpty(set.metallicPath)) set.metallicPath = assetPath;
                break;
            case TextureType.Roughness:
                if (string.IsNullOrEmpty(set.roughnessPath)) set.roughnessPath = assetPath;
                break;
            case TextureType.AO:
                if (string.IsNullOrEmpty(set.aoPath)) set.aoPath = assetPath;
                break;
            case TextureType.Emission:
                if (string.IsNullOrEmpty(set.emissionPath)) set.emissionPath = assetPath;
                break;
        }
    }

    private bool CreateOrUpdateMaterial(TextureSet set)
    {
        Shader shader = Shader.Find("Universal Render Pipeline/Lit");
        if (shader == null)
        {
            Debug.LogError("URP Lit shader not found. Make sure URP is installed and active.");
            return false;
        }

        string materialFolder = createMaterialInSameFolder ? set.folderPath : "Assets";
        string materialPath = $"{materialFolder}/{set.materialKey}.mat";

        Material material = AssetDatabase.LoadAssetAtPath<Material>(materialPath);
        bool created = false;

        if (material == null)
        {
            material = new Material(shader);
            AssetDatabase.CreateAsset(material, materialPath);
            created = true;
        }
        else
        {
            if (!overwriteExistingMaterial)
            {
                Debug.Log($"Skip existing material: {materialPath}");
                return false;
            }

            if (material.shader != shader)
                material.shader = shader;
        }

        ApplyTexturesToMaterial(material, set);

        EditorUtility.SetDirty(material);
        AssetDatabase.SaveAssets();

        Debug.Log($"{(created ? "Created" : "Updated")} material: {materialPath}");
        return created;
    }

    private void ApplyTexturesToMaterial(Material material, TextureSet set)
    {
        Texture2D albedo = LoadTexture(set.albedoPath);
        Texture2D normal = LoadTexture(set.normalPath);
        Texture2D metallic = LoadTexture(set.metallicPath);
        Texture2D roughness = LoadTexture(set.roughnessPath);
        Texture2D ao = LoadTexture(set.aoPath);
        Texture2D emission = LoadTexture(set.emissionPath);

        if (ShouldAssign(material, "_BaseMap", albedo))
        {
            material.SetTexture("_BaseMap", albedo);
        }

        if (ShouldAssign(material, "_BumpMap", normal))
        {
            material.EnableKeyword("_NORMALMAP");
            material.SetTexture("_BumpMap", normal);
        }

        if (ShouldAssign(material, "_OcclusionMap", ao))
        {
            material.SetTexture("_OcclusionMap", ao);
            material.SetFloat("_OcclusionStrength", 1f);
        }

        if (ShouldAssign(material, "_EmissionMap", emission))
        {
            material.EnableKeyword("_EMISSION");
            material.SetTexture("_EmissionMap", emission);
            material.SetColor("_EmissionColor", Color.white);
        }

        // URP Lit uses metallic workflow:
        // Metallic in R, Smoothness in A
        if (metallic != null || roughness != null)
        {
            string packedPath = GeneratePackedMetallicSmoothnessMap(set, metallic, roughness);
            Texture2D packedMap = LoadTexture(packedPath);

            if (ShouldAssign(material, "_MetallicGlossMap", packedMap))
            {
                material.SetFloat("_Metallic", 1f);
                material.SetTexture("_MetallicGlossMap", packedMap);
                material.EnableKeyword("_METALLICSPECGLOSSMAP");
                material.SetFloat("_Smoothness", 1f);
            }
        }
    }

    private bool ShouldAssign(Material material, string propertyName, Texture texture)
    {
        if (texture == null) return false;
        if (overwriteMaterialTextureSlots) return true;

        Texture existing = material.GetTexture(propertyName);
        return existing == null;
    }

    private Texture2D LoadTexture(string path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }

    private string GeneratePackedMetallicSmoothnessMap(TextureSet set, Texture2D metallicTex, Texture2D roughnessTex)
    {
        int width = 1024;
        int height = 1024;

        if (metallicTex != null)
        {
            width = metallicTex.width;
            height = metallicTex.height;
        }
        else if (roughnessTex != null)
        {
            width = roughnessTex.width;
            height = roughnessTex.height;
        }

        Texture2D metallicReadable = metallicTex != null ? GetReadableCopy(metallicTex, width, height) : null;
        Texture2D roughnessReadable = roughnessTex != null ? GetReadableCopy(roughnessTex, width, height) : null;

        Texture2D packed = new Texture2D(width, height, TextureFormat.RGBA32, false, true);

        Color[] pixels = new Color[width * height];
        Color[] metallicPixels = metallicReadable != null ? metallicReadable.GetPixels() : null;
        Color[] roughnessPixels = roughnessReadable != null ? roughnessReadable.GetPixels() : null;

        for (int i = 0; i < pixels.Length; i++)
        {
            float metallicValue = metallicPixels != null ? metallicPixels[i].r : 0f;
            float roughnessValue = roughnessPixels != null ? roughnessPixels[i].r : 1f;
            float smoothnessValue = 1f - roughnessValue;

            pixels[i] = new Color(metallicValue, 0f, 0f, smoothnessValue);
        }

        packed.SetPixels(pixels);
        packed.Apply();

        string outputFolder = set.folderPath;
        string packedPath = $"{outputFolder}/{set.materialKey}_MetallicSmoothness.png";
        string absolutePath = Path.GetFullPath(packedPath);

        byte[] png = packed.EncodeToPNG();
        File.WriteAllBytes(absolutePath, png);

        DestroyImmediate(packed);
        if (metallicReadable != null) DestroyImmediate(metallicReadable);
        if (roughnessReadable != null) DestroyImmediate(roughnessReadable);

        AssetDatabase.ImportAsset(packedPath);
        ApplyTextureImportSettings(packedPath, TextureType.Metallic);

        return packedPath;
    }

    private Texture2D GetReadableCopy(Texture2D source, int width, int height)
    {
        RenderTexture rt = RenderTexture.GetTemporary(width, height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
        Graphics.Blit(source, rt);

        RenderTexture previous = RenderTexture.active;
        RenderTexture.active = rt;

        Texture2D readable = new Texture2D(width, height, TextureFormat.RGBA32, false, true);
        readable.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        readable.Apply();

        RenderTexture.active = previous;
        RenderTexture.ReleaseTemporary(rt);

        return readable;
    }

    private void ApplyTextureImportSettings(string assetPath, TextureType texType)
    {
        AssetImporter importer = AssetImporter.GetAtPath(assetPath);
        TextureImporter textureImporter = importer as TextureImporter;
        if (textureImporter == null) return;

        bool changed = false;

        switch (texType)
        {
            case TextureType.Normal:
                if (textureImporter.textureType != TextureImporterType.NormalMap)
                {
                    textureImporter.textureType = TextureImporterType.NormalMap;
                    changed = true;
                }
                break;

            case TextureType.Metallic:
            case TextureType.Roughness:
            case TextureType.AO:
                if (textureImporter.sRGBTexture)
                {
                    textureImporter.sRGBTexture = false;
                    changed = true;
                }
                break;

            case TextureType.Emission:
            case TextureType.Albedo:
                if (!textureImporter.sRGBTexture)
                {
                    textureImporter.sRGBTexture = true;
                    changed = true;
                }
                break;
        }

        if (changed)
        {
            EditorUtility.SetDirty(textureImporter);
            textureImporter.SaveAndReimport();
        }
    }

    private TextureType IdentifyTextureType(string fileName)
    {
        string lower = fileName.ToLowerInvariant();

        if (ContainsAny(lower, "basecolor", "albedo", "diffuse", "base_color", "color", "col", "texture"))
            return TextureType.Albedo;

        if (ContainsAny(lower, "normal", "nrm", "nor"))
            return TextureType.Normal;

        if (ContainsAny(lower, "metallic", "metal", "mtl"))
            return TextureType.Metallic;

        if (ContainsAny(lower, "roughness", "rough", "rgh"))
            return TextureType.Roughness;

        if (ContainsAny(lower, "ao", "occlusion", "ambientocclusion"))
            return TextureType.AO;

        if (ContainsAny(lower, "emission", "emissive", "emit"))
            return TextureType.Emission;

        return TextureType.Unknown;
    }

    private string ExtractMaterialKey(string fileName, TextureType texType)
    {
        string lower = fileName.ToLowerInvariant();
        string[] suffixes = GetSuffixCandidates(texType);

        foreach (string suffix in suffixes)
        {
            int index = lower.LastIndexOf(suffix, StringComparison.Ordinal);
            if (index > 0)
            {
                string raw = fileName.Substring(0, index);
                raw = raw.TrimEnd('_', '-', ' ');
                return raw;
            }
        }

        return fileName;
    }

    private string[] GetSuffixCandidates(TextureType texType)
    {
        switch (texType)
        {
            case TextureType.Albedo:
                return new[] { "basecolor", "albedo", "diffuse", "base_color", "color", "col", "texture" };
            case TextureType.Normal:
                return new[] { "normal", "nrm", "nor" };
            case TextureType.Metallic:
                return new[] { "metallic", "metal", "mtl" };
            case TextureType.Roughness:
                return new[] { "roughness", "rough", "rgh" };
            case TextureType.AO:
                return new[] { "ambientocclusion", "occlusion", "ao" };
            case TextureType.Emission:
                return new[] { "emission", "emissive", "emit" };
            default:
                return Array.Empty<string>();
        }
    }

    private bool ContainsAny(string source, params string[] keywords)
    {
        foreach (string k in keywords)
        {
            if (source.Contains(k))
                return true;
        }
        return false;
    }
}